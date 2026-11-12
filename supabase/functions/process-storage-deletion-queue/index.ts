// ============================================================================
// Supabase Edge Function: process-storage-deletion-queue
// ============================================================================
// Description:
//   Asynchronously processes pending physical file deletions from the
//   public.storage_deletion_queue using the official Supabase Storage API.
//
// Security & Operational Features:
// 1. Dedicated Worker Secret Authentication:
//    Requires an x-worker-secret header matching STORAGE_QUEUE_WORKER_SECRET
//    (or service_role bearer authorization). Rejects unauthorized invocations
//    with HTTP 401 before any database or storage operations occur.
// 2. Service-Role Isolation:
//    Uses SUPABASE_SERVICE_ROLE_KEY exclusively on the server side to invoke
//    the Storage API. Credentials are NEVER exposed to client or Flutter apps.
// 3. Concurrency Safety:
//    Claims batches atomically using claim_storage_deletion_batch() with
//    FOR UPDATE SKIP LOCKED to prevent duplicate simultaneous executions.
// 4. Robust Error Handling & Exponential Backoff:
//    Records attempts and calculates exponential backoff via
//    complete_storage_deletion_item(). Failed items are retried up to max_attempts.
// 5. Batching by Bucket:
//    Groups files by bucket_id and executes batch removals through
//    supabase.storage.from(bucket).remove(paths).
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-worker-secret",
};

interface QueueBatchItem {
  id: string;
  bucket_id: string;
  file_path: string;
  attempts: number;
}

function secureTimingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aBuf = enc.encode(a);
  const bBuf = enc.encode(b);
  if (aBuf.byteLength !== bBuf.byteLength) {
    return false;
  }
  let result = 0;
  for (let i = 0; i < aBuf.byteLength; i++) {
    result |= aBuf[i] ^ bBuf[i];
  }
  return result === 0;
}

serve(async (req: Request) => {
  // 1. Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const workerSecret = Deno.env.get("STORAGE_QUEUE_WORKER_SECRET");

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("[StorageQueueWorker] Missing required server configuration");
      return new Response(
        JSON.stringify({
          success: false,
          error: "Server configuration missing required environment variables",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 2. Worker Secret / Service-Role Authentication
    // Rejects unauthorized calls before claiming queue jobs
    const incomingWorkerSecret = req.headers.get("x-worker-secret");
    const authHeader = req.headers.get("authorization") || "";
    const bearerToken = authHeader.replace(/^Bearer\s+/i, "").trim();

    let isAuthorized = false;

    // Check shared worker secret if configured
    if (workerSecret && incomingWorkerSecret) {
      isAuthorized = secureTimingSafeEqual(workerSecret, incomingWorkerSecret);
    }

    // Also authorize if valid service_role key provided in bearer header
    if (!isAuthorized && bearerToken && bearerToken === serviceRoleKey) {
      isAuthorized = true;
    }

    if (!isAuthorized) {
      console.warn("[StorageQueueWorker] Unauthorized invocation rejected: invalid or missing credentials");
      return new Response(
        JSON.stringify({
          success: false,
          error: "Unauthorized: Invalid or missing worker authentication",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 3. Optional batch size from request body
    let batchSize = 50;
    if (req.method === "POST") {
      try {
        const body = await req.json();
        if (typeof body?.batch_size === "number" && body.batch_size > 0) {
          batchSize = Math.min(body.batch_size, 100);
        }
      } catch (_) {
        // Body is optional; default batch size applies
      }
    }

    // 4. Initialize privileged Supabase client
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // 5. Atomically claim batch of pending items (FOR UPDATE SKIP LOCKED)
    const { data: claimedItems, error: claimError } = await adminClient.rpc(
      "claim_storage_deletion_batch",
      { p_batch_size: batchSize }
    );

    if (claimError) {
      console.error("[StorageQueueWorker] Error claiming batch:", claimError);
      return new Response(
        JSON.stringify({ success: false, error: claimError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const items: QueueBatchItem[] = (claimedItems as QueueBatchItem[]) || [];
    if (items.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          processed: 0,
          message: "Storage deletion queue is empty or no items due for retry",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    console.log(`[StorageQueueWorker] Claimed ${items.length} items for processing.`);

    // 6. Group claimed files by bucket
    const bucketMap = new Map<string, QueueBatchItem[]>();
    for (const item of items) {
      const bucket = item.bucket_id || "documents";
      if (!bucketMap.has(bucket)) {
        bucketMap.set(bucket, []);
      }
      bucketMap.get(bucket)!.push(item);
    }

    let totalSucceeded = 0;
    let totalFailed = 0;
    const itemResults: Array<{ id: string; success: boolean; error?: string }> = [];

    // 7. Process each bucket's batch through official Supabase Storage API
    for (const [bucket, bucketItems] of bucketMap.entries()) {
      const paths = bucketItems.map((i) => i.file_path);

      try {
        const { error: removeError } = await adminClient.storage
          .from(bucket)
          .remove(paths);

        if (removeError) {
          console.error(`[StorageQueueWorker] Storage API error for bucket '${bucket}':`, removeError);
          // Mark all items in this bucket as failed with exponential backoff
          for (const item of bucketItems) {
            await adminClient.rpc("complete_storage_deletion_item", {
              p_id: item.id,
              p_success: false,
              p_error_message: removeError.message || "Storage API removal failed",
            });
            totalFailed++;
            itemResults.push({
              id: item.id,
              success: false,
              error: removeError.message,
            });
          }
        } else {
          // Successfully removed from object storage and storage.objects
          for (const item of bucketItems) {
            await adminClient.rpc("complete_storage_deletion_item", {
              p_id: item.id,
              p_success: true,
              p_error_message: null,
            });
            totalSucceeded++;
            itemResults.push({
              id: item.id,
              success: true,
            });
          }
        }
      } catch (err: any) {
        console.error(`[StorageQueueWorker] Unexpected exception in bucket '${bucket}':`, err);
        for (const item of bucketItems) {
          await adminClient.rpc("complete_storage_deletion_item", {
            p_id: item.id,
            p_success: false,
            p_error_message: err?.message || String(err),
          });
          totalFailed++;
          itemResults.push({
            id: item.id,
            success: false,
            error: err?.message || String(err),
          });
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        processed: items.length,
        succeeded: totalSucceeded,
        failed: totalFailed,
        results: itemResults,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (globalErr: any) {
    console.error("[StorageQueueWorker] Uncaught worker error:", globalErr);
    return new Response(
      JSON.stringify({
        success: false,
        error: globalErr?.message || "Internal server error during queue processing",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
