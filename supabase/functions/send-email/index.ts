// ============================================================================
// Supabase Edge Function: send-email
// ============================================================================
// Security Model & Architecture:
// 1. In-Code Caller Authentication:
//    Verifies the calling user's Supabase JWT token via auth.getUser().
//    Never assumes possessing a service-role key or gateway bypass constitutes authorization.
// 2. Multi-Tenant Organization Authorization:
//    Resolves the caller's organization_id and role from public.profiles.
//    Verifies that the target action strictly belongs to the caller's organization
//    (or caller is platform admin). Cross-tenant email dispatch is forbidden.
// 3. Secrets Protection:
//    RESEND_API_KEY is retrieved server-side via Deno.env and NEVER exposed or logged.
// 4. Strict Delivery Confirmation:
//    Delivery success is reported ONLY when the provider confirms HTTP 200/201
//    and returns a valid message ID. Updates action_email_reminders audit state.
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-scheduler-secret",
};

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

interface EmailPayload {
  action: string;
  to?: string;
  subject?: string;
  html?: string;
  text?: string;
  recipient_type?: string;
  action_id?: string;
  reminder_id?: string;
  organization_id?: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const defaultFromEmail =
      Deno.env.get("RESEND_FROM_EMAIL") || "ActionFlow <onboarding@resend.dev>";
    const schedulerSecret = Deno.env.get("ACTIONFLOW_SCHEDULER_SECRET");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Server configuration error: Missing Supabase environment variables",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    let body: EmailPayload;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid JSON body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { action } = body;

    // ------------------------------------------------------------------------
    // 1. Verify Caller Authentication:
    //    Path A: Dedicated Server-to-Server Scheduler Secret for autonomous cron
    //    Path B: User Session JWT for authenticated Managers and Admins
    // ------------------------------------------------------------------------
    let isScheduledInvocation = false;
    let callerUser: any = null;
    let callerProfile: any = null;
    let callerRole = "";
    let isPlatformAdmin = false;
    let isAdminRpc = false;
    let isManagerRpc = false;
    let userClient: any = null;

    // Privileged service-role client for authoritative data lookup & worker claim
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey);

    const hasSchedulerHeader = req.headers.has("x-scheduler-secret");

    if (hasSchedulerHeader) {
      const schedulerHeader = req.headers.get("x-scheduler-secret")?.trim() || "";

      // Path A: Dedicated Server-to-Server Scheduler Path
      if (!schedulerSecret || schedulerSecret.trim().length < 16) {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              "Server configuration error: ACTIONFLOW_SCHEDULER_SECRET is not configured or insufficient in backend environment (minimum 16 characters).",
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (schedulerHeader.length < 16 || !secureTimingSafeEqual(schedulerHeader, schedulerSecret.trim())) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Unauthorized: Invalid scheduler secret",
          }),
          {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // Security Invariant: The scheduler secret is strictly restricted to reminder batch processing
      if (action !== "process_due_reminders") {
        return new Response(
          JSON.stringify({
            success: false,
            error:
              "ActionFlow Security Violation: Scheduler secret is only permitted for 'process_due_reminders'.",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      isScheduledInvocation = true;
      isPlatformAdmin = true;
      callerRole = "scheduler";
    } else {
      // Path B: Standard User Session JWT Authorization Path
      const authHeader = req.headers.get("Authorization");
      if (!authHeader) {
        return new Response(
          JSON.stringify({ success: false, error: "Unauthorized: Missing Authorization header" }),
          {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const token = authHeader.replace(/^Bearer\s+/i, "");
      userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader } },
      });

      const {
        data: { user: verifiedUser },
        error: callerError,
      } = await userClient.auth.getUser(token);

      if (callerError || !verifiedUser) {
        return new Response(
          JSON.stringify({ success: false, error: "Unauthorized: Invalid or expired session token" }),
          {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
      callerUser = verifiedUser;

      // Resolve caller profile using ONLY the authenticated caller's JWT user ID
      const { data: profileRow, error: profError } = await supabaseAdmin
        .from("profiles")
        .select("id, organization_id, status, is_active, role_id")
        .eq("id", callerUser.id)
        .maybeSingle();

      if (profError || !profileRow) {
        return new Response(
          JSON.stringify({ success: false, error: "Forbidden: Active user profile required" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
      callerProfile = profileRow;

      // Explicitly require: profile is active
      const isProfileActive =
        callerProfile.is_active === true &&
        (callerProfile.status?.toLowerCase() === "active" ||
          callerProfile.status === null ||
          callerProfile.status === undefined);

      if (!isProfileActive) {
        return new Response(
          JSON.stringify({ success: false, error: "Forbidden: Active user profile required" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // Resolve caller role from roles table
      if (callerProfile.role_id) {
        const { data: roleRow } = await supabaseAdmin
          .from("roles")
          .select("code")
          .eq("id", callerProfile.role_id)
          .maybeSingle();
        if (roleRow?.code) {
          callerRole = roleRow.code.toLowerCase();
        }
      }

      const [{ data: platAdminData }, { data: adminRpcData }, { data: mgrRpcData }] =
        await Promise.all([
          userClient.rpc("is_platform_admin"),
          userClient.rpc("is_admin"),
          userClient.rpc("is_manager"),
        ]);

      isPlatformAdmin = Boolean(platAdminData);
      isAdminRpc = Boolean(adminRpcData);
      isManagerRpc = Boolean(mgrRpcData);
    }

    // ------------------------------------------------------------------------
    // Action 1: test_provider_status
    // ------------------------------------------------------------------------
    if (action === "test_provider_status") {
      const isConfigured = Boolean(resendApiKey && resendApiKey.trim().length > 0);
      return new Response(
        JSON.stringify({
          configured: isConfigured,
          provider: "resend",
          status: isConfigured ? "configured" : "not_configured",
          message: isConfigured
            ? "Resend email provider is configured."
            : "RESEND_API_KEY is not configured in Supabase secrets.",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Verify provider configured for email-sending operations
    if (!resendApiKey || resendApiKey.trim() === "") {
      return new Response(
        JSON.stringify({
          success: false,
          status: "not_configured",
          error: "Email provider (Resend) is not configured in Supabase secrets.",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ------------------------------------------------------------------------
    // Action 2: send_action_reminder
    // ------------------------------------------------------------------------
    if (action === "send_action_reminder") {
      const { action_id, reminder_id } = body;

      if (!action_id || !action_id.trim()) {
        return new Response(
          JSON.stringify({ success: false, error: "Missing required action_id." }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 2.1 Fetch action record
      const { data: act, error: actError } = await supabaseAdmin
        .from("actions")
        .select("*, external_action_recipients(*)")
        .eq("id", action_id.trim())
        .single();

      if (actError || !act) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Action record not found: ${actError?.message || "Not found"}`,
          }),
          {
            status: 404,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 2.2 Strict Multi-Tenant Enforcement: action MUST belong to caller's organization
      if (!isPlatformAdmin && act.organization_id !== callerProfile.organization_id) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "ActionFlow Security Violation: Cross-organization email dispatch forbidden.",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // 2.3 Resolve recipient email, subject, body from database records
      let recipientEmail = "";
      let recipientName = "";
      let emailSubject = "";
      let emailBody = "";
      let reminderRecordId: string | null = reminder_id || null;

      if (reminder_id) {
        const { data: reminder, error: remError } = await supabaseAdmin
          .from("action_email_reminders")
          .select("*")
          .eq("id", reminder_id)
          .eq("action_id", action_id.trim())
          .single();

        if (remError || !reminder) {
          return new Response(
            JSON.stringify({
              success: false,
              error: `Reminder job not found or does not match action: ${remError?.message}`,
            }),
            {
              status: 404,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }

        recipientEmail = reminder.recipient_email;
        recipientName = reminder.recipient_name;
        emailSubject = reminder.email_subject;
        emailBody = reminder.email_body;
      } else {
        // Fetch latest pending reminder or resolve from action record
        const { data: reminder } = await supabaseAdmin
          .from("action_email_reminders")
          .select("*")
          .eq("action_id", action_id.trim())
          .eq("status", "pending")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();

        if (reminder) {
          reminderRecordId = reminder.id;
          recipientEmail = reminder.recipient_email;
          recipientName = reminder.recipient_name;
          emailSubject = reminder.email_subject;
          emailBody = reminder.email_body;
        } else {
          if (act.recipient_type === "external" && act.external_action_recipients) {
            recipientEmail = act.external_action_recipients.email;
            recipientName = act.external_action_recipients.full_name;
          } else if (act.assigned_to) {
            const { data: prof } = await supabaseAdmin
              .from("profiles")
              .select("email, full_name")
              .eq("id", act.assigned_to)
              .maybeSingle();
            if (prof) {
              recipientEmail = prof.email;
              recipientName = prof.full_name;
            }
          }

          emailSubject = `ActionFlow Reminder: [${act.action_number || act.id}] ${act.title}`;
          emailBody = `Hello ${recipientName || "Assignee"},\n\nThis is a notification regarding Action #${act.action_number || act.id}: ${act.title}.\nStatus: ${act.status} (${act.percent_complete}%)\nDue Date: ${act.target_date || act.due_date || "Not set"}\n\nPlease review and update your progress in ActionFlow.\n\nThank you,\nActionFlow Team`;
        }
      }

      if (!recipientEmail || !recipientEmail.trim()) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Recipient email could not be resolved for this action.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (reminderRecordId) {
        await supabaseAdmin
          .from("action_email_reminders")
          .update({
            status: "processing",
            updated_at: new Date().toISOString(),
          })
          .eq("id", reminderRecordId);
      }

      // 2.4 Dispatch via Resend Provider
      const resendRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${resendApiKey.trim()}`,
          "Content-Type": "application/json",
          "Idempotency-Key": `rem_${reminderRecordId || action_id}`,
        },
        body: JSON.stringify({
          from: defaultFromEmail,
          to: [recipientEmail.trim()],
          subject: emailSubject,
          text: emailBody,
          html: `<div style="font-family: sans-serif; line-height: 1.6; color: #1e293b;">
            <div style="background-color: #1e3a8a; color: white; padding: 16px 20px; border-radius: 8px 8px 0 0;">
              <h2 style="margin: 0; font-size: 18px;">ActionFlow HSE Action Tracker</h2>
            </div>
            <div style="padding: 20px; border: 1px solid #e2e8f0; border-top: none; border-radius: 0 0 8px 8px;">
              <pre style="white-space: pre-wrap; font-family: inherit; font-size: 14px; margin: 0 0 20px 0;">${emailBody}</pre>
            </div>
          </div>`,
        }),
      });

      const resData = await resendRes.json();

      if (!resendRes.ok) {
        const errorMsg =
          resData?.message ||
          resData?.error ||
          `Resend API error: ${resendRes.status}`;
        if (reminderRecordId) {
          await supabaseAdmin
            .from("action_email_reminders")
            .update({
              status: "failed",
              failure_reason: errorMsg,
              updated_at: new Date().toISOString(),
            })
            .eq("id", reminderRecordId);
        }

        return new Response(
          JSON.stringify({ success: false, status: "failed", error: errorMsg }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (reminderRecordId) {
        await supabaseAdmin
          .from("action_email_reminders")
          .update({
            status: "sent",
            sent_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq("id", reminderRecordId);
      }

      return new Response(
        JSON.stringify({
          success: true,
          status: "sent",
          message_id: resData.id,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ------------------------------------------------------------------------
    // Action 3: send_single_email
    // ------------------------------------------------------------------------
    if (action === "send_single_email") {
      // Must be a manager or admin in the organization
      const isManagerOrAdmin =
        Boolean(isPlatformAdmin) ||
        Boolean(isAdminRpc) ||
        Boolean(isManagerRpc) ||
        ["manager", "admin", "company_admin"].includes(callerRole);

      if (!isManagerOrAdmin) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "ActionFlow Security Violation: Only managers or administrators may dispatch notification emails.",
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // If action_id is supplied, enforce multi-tenant organization scoping
      if (body.action_id && body.action_id.trim()) {
        const { data: act } = await supabaseAdmin
          .from("actions")
          .select("organization_id")
          .eq("id", body.action_id.trim())
          .maybeSingle();

        if (act && !isPlatformAdmin && act.organization_id !== callerProfile.organization_id) {
          return new Response(
            JSON.stringify({
              success: false,
              error: "ActionFlow Security Violation: Cross-organization email dispatch forbidden.",
            }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }
      }

      const { to, subject, html, text } = body;

      if (!to || !to.trim() || !subject || !subject.trim() || !html || !html.trim()) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Missing required fields: to, subject, or html.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(to.trim())) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Invalid recipient email address format.",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const resendRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${resendApiKey.trim()}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: defaultFromEmail,
          to: [to.trim()],
          subject: subject.trim(),
          html: html,
          ...(text ? { text } : {}),
        }),
      });

      const resData = await resendRes.json();

      if (!resendRes.ok) {
        return new Response(
          JSON.stringify({
            success: false,
            status: "failed",
            error:
              resData?.message ||
              resData?.error ||
              `Resend HTTP error ${resendRes.status}`,
          }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          status: "sent",
          message_id: resData.id,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ------------------------------------------------------------------------
    // Action 4: process_due_reminders (Daily / Scheduled Reminder Batch Processor)
    // ------------------------------------------------------------------------
    if (action === "process_due_reminders") {
      if (!isScheduledInvocation) {
        const isManagerOrAdmin =
          Boolean(isPlatformAdmin) ||
          Boolean(isAdminRpc) ||
          Boolean(isManagerRpc) ||
          ["manager", "admin", "company_admin"].includes(callerRole);

        if (!isManagerOrAdmin) {
          return new Response(
            JSON.stringify({
              success: false,
              error:
                "ActionFlow Security Violation: Only managers or administrators may trigger batch reminder processing.",
            }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }
      }

      const nowIso = new Date().toISOString();
      const leaseSeconds = 600; // 10 minutes lease timeout
      const staleCutoffMs = Date.now() - leaseSeconds * 1000;
      const workerId = `worker_${crypto.randomUUID()}`;

      // Query eligible reminders:
      // Status in pending or processing, scheduled_at <= now, limited to 50 per batch
      let query = supabaseAdmin
        .from("action_email_reminders")
        .select("*, actions(*)")
        .in("status", ["pending", "processing"])
        .lte("scheduled_at", nowIso)
        .order("scheduled_at", { ascending: true })
        .limit(50);

      if (!isScheduledInvocation && callerProfile?.organization_id && !isPlatformAdmin) {
        query = query.eq("organization_id", callerProfile.organization_id);
      } else if (body.organization_id) {
        query = query.eq("organization_id", body.organization_id);
      }

      const { data: dueReminders, error: queryError } = await query;

      if (queryError) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Failed to query due reminders: ${queryError.message}`,
          }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      let processedCount = 0;
      let sentCount = 0;
      let failedCount = 0;
      let cancelledCount = 0;
      const results: Array<{ id: string; status: string; recipient: string; error?: string }> = [];

      for (const rem of dueReminders || []) {
        // Pre-filter: Check eligibility before attempting claim
        const maxAttempts = rem.max_attempts || 3;
        const currentAttempts = rem.attempt_count || 0;

        // If reminder has already exceeded max attempts, skip
        if (currentAttempts >= maxAttempts) {
          continue;
        }

        // If status is 'processing', only eligible if demonstrably stale (> 10 minutes)
        if (rem.status === "processing") {
          const claimTimestamp = new Date(rem.claimed_at || rem.updated_at).getTime();
          if (claimTimestamp > staleCutoffMs) {
            // An active worker still holds the lease; do not claim concurrently
            continue;
          }
        }

        // If status is 'pending' but has a future retry backoff time, wait
        if (rem.status === "pending" && rem.next_retry_at) {
          if (new Date(rem.next_retry_at).getTime() > Date.now()) {
            continue;
          }
        }

        processedCount++;
        const act = rem.actions;

        // 4.1 If action is closed or reminders are disabled, cancel the reminder
        if (
          !act ||
          act.status?.toLowerCase() === "closed" ||
          act.is_closed === true ||
          act.percent_complete === 100 ||
          act.email_reminder_enabled === false
        ) {
          await supabaseAdmin
            .from("action_email_reminders")
            .update({
              status: "cancelled",
              updated_at: new Date().toISOString(),
            })
            .eq("id", rem.id)
            .in("status", ["pending", "processing"]);

          cancelledCount++;
          results.push({
            id: rem.id,
            status: "cancelled",
            recipient: rem.recipient_email,
          });
          continue;
        }

        // 4.2 Atomically claim or recover the reminder job
        let isClaimed = false;
        let rpcExecuted = false;
        let attemptNumber = currentAttempts + 1;

        try {
          const { data: claimData, error: claimError } = await supabaseAdmin.rpc(
            "claim_action_email_reminder",
            {
              p_reminder_id: rem.id,
              p_action_id: rem.action_id,
              p_organization_id: rem.organization_id,
              p_worker_id: workerId,
              p_lease_seconds: leaseSeconds,
            }
          );
          if (!claimError) {
            rpcExecuted = true;
            if (claimData?.success === true) {
              isClaimed = true;
              attemptNumber = claimData.attempt || (currentAttempts + 1);
            } else {
              // Stored procedure rejected claim (lease active, closed, or claimed)
              continue;
            }
          }
        } catch (_) {
          // Fallback if stored procedure unmigrated or unavailable
        }

        if (!rpcExecuted && !isClaimed) {
          const { data: updateData, error: updateErr } = await supabaseAdmin
            .from("action_email_reminders")
            .update({
              status: "processing",
              claimed_at: nowIso,
              claimed_by: workerId,
              attempt_count: currentAttempts + 1,
              last_attempt_at: nowIso,
              updated_at: nowIso,
            })
            .eq("id", rem.id)
            .eq("status", rem.status)
            .lte("scheduled_at", nowIso)
            .select();

          if (updateErr || !updateData || updateData.length === 0) {
            // Already claimed by another worker or not eligible
            continue;
          }
          isClaimed = true;
        }

        // 4.3 Validate provider credentials before dispatch
        if (!resendApiKey || resendApiKey.trim() === "") {
          // Permanent failure: missing server secret cannot be resolved by retry
          // Fencing invariant: only update if this worker still holds the claim
          const { data: updateData } = await supabaseAdmin
            .from("action_email_reminders")
            .update({
              status: "failed",
              is_retryable: false,
              next_retry_at: null,
              failure_reason: "Resend API key not configured in backend environment",
              updated_at: new Date().toISOString(),
            })
            .eq("id", rem.id)
            .eq("claimed_by", workerId)
            .eq("status", "processing")
            .select();

          if (!updateData || updateData.length === 0) {
            console.warn(`[Worker ${workerId}] Lost lease for reminder ${rem.id} during configuration check; update discarded.`);
            continue;
          }

          failedCount++;
          results.push({
            id: rem.id,
            status: "failed",
            recipient: rem.recipient_email,
            error: "Resend API key not configured",
          });
          continue;
        }

        const emailSubject = rem.email_subject || `ActionFlow Reminder: [${act.action_number || act.id}] ${act.title || act.subject}`;
        const emailBody = rem.email_body || `Pending HSSE action reminder for ${rem.recipient_name}`;
        // Stable idempotency key for Resend (deduplicates within provider's 24h window)
        const idempotencyKey = rem.idempotency_key || `rem_${rem.id}`;

        try {
          const resendRes = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${resendApiKey.trim()}`,
              "Content-Type": "application/json",
              "Idempotency-Key": idempotencyKey,
            },
            body: JSON.stringify({
              from: defaultFromEmail,
              to: [rem.recipient_email.trim()],
              subject: emailSubject,
              text: emailBody,
              html: `<div style="font-family: sans-serif; line-height: 1.6; color: #1e293b;">
                <div style="background-color: #1e3a8a; color: white; padding: 16px 20px; border-radius: 8px 8px 0 0;">
                  <h2 style="margin: 0; font-size: 18px;">ActionFlow HSE Action Tracker</h2>
                </div>
                <div style="padding: 20px; border: 1px solid #e2e8f0; border-top: none; border-radius: 0 0 8px 8px;">
                  <pre style="white-space: pre-wrap; font-family: inherit; font-size: 14px; margin: 0 0 20px 0;">${emailBody}</pre>
                </div>
              </div>`,
            }),
          });

          const resData = await resendRes.json();

          if (resendRes.ok) {
            // Success: delivery accepted by provider
            // Fencing invariant: update status ONLY if worker still owns the processing lease
            const { data: updateData } = await supabaseAdmin
              .from("action_email_reminders")
              .update({
                status: "sent",
                sent_at: new Date().toISOString(),
                next_retry_at: null,
                failure_reason: null,
                updated_at: new Date().toISOString(),
              })
              .eq("id", rem.id)
              .eq("claimed_by", workerId)
              .eq("status", "processing")
              .select();

            if (!updateData || updateData.length === 0) {
              // Lease expired and was reclaimed by another worker while waiting for provider response.
              // Due to idempotencyKey, the second worker will get the cached provider response.
              console.warn(`[Worker ${workerId}] Delivered reminder ${rem.id} to provider, but lease was lost before DB update. Discarding stale completion update.`);
              results.push({
                id: rem.id,
                status: "sent_uncertain_lease",
                recipient: rem.recipient_email,
              });
              continue;
            }

            sentCount++;
            results.push({
              id: rem.id,
              status: "sent",
              recipient: rem.recipient_email,
            });

            // 4.4 Synchronize matching in-app notification for internal users
            if (rem.profile_id) {
              try {
                await supabaseAdmin.from("notifications").insert({
                  user_id: rem.profile_id,
                  organization_id: rem.organization_id,
                  title: emailSubject,
                  message: emailBody,
                  event_type: "due_date_approaching",
                  action_id: act.action_number || act.id,
                  idempotency_key: `batch_rem_${rem.id}`,
                  is_read: false,
                });
              } catch (_) {
                // Ignore if notifications table unmigrated or duplicate
              }
            }
          } else {
            // Provider returned non-2xx HTTP status
            const statusCode = resendRes.status;
            const errorMsg = resData?.message || resData?.error || `Resend error HTTP ${statusCode}`;
            
            // Error Classification:
            // 4xx (except 429) = Permanent failure (Bad Request, Unauthorized, Unprocessable Entity)
            // 429 or 5xx = Retryable failure (Rate Limit, Server Error, Gateway Timeout)
            const isRetryable = statusCode === 429 || (statusCode >= 500 && statusCode < 600);

            if (isRetryable && attemptNumber < maxAttempts) {
              // Bounded exponential backoff: attempt 1 -> 15m, attempt 2 -> 30m, max 60m
              const backoffMinutes = Math.min(15 * Math.pow(2, attemptNumber - 1), 60);
              const nextRetryIso = new Date(Date.now() + backoffMinutes * 60 * 1000).toISOString();

              const { data: updateData } = await supabaseAdmin
                .from("action_email_reminders")
                .update({
                  status: "pending",
                  is_retryable: true,
                  next_retry_at: nextRetryIso,
                  failure_reason: `[Attempt ${attemptNumber}/${maxAttempts} retryable HTTP ${statusCode}]: ${errorMsg}`,
                  updated_at: new Date().toISOString(),
                })
                .eq("id", rem.id)
                .eq("claimed_by", workerId)
                .eq("status", "processing")
                .select();

              if (!updateData || updateData.length === 0) {
                console.warn(`[Worker ${workerId}] Lost lease for reminder ${rem.id} during retry scheduling; update discarded.`);
                continue;
              }

              results.push({
                id: rem.id,
                status: "retry_scheduled",
                recipient: rem.recipient_email,
                error: `HTTP ${statusCode} (Retrying at ${nextRetryIso})`,
              });
            } else {
              // Non-retryable or max attempts exhausted
              const { data: updateData } = await supabaseAdmin
                .from("action_email_reminders")
                .update({
                  status: "failed",
                  is_retryable: false,
                  next_retry_at: null,
                  failure_reason: attemptNumber >= maxAttempts
                    ? `[Max retries exceeded (${maxAttempts})]: ${errorMsg}`
                    : `[Permanent failure HTTP ${statusCode}]: ${errorMsg}`,
                  updated_at: new Date().toISOString(),
                })
                .eq("id", rem.id)
                .eq("claimed_by", workerId)
                .eq("status", "processing")
                .select();

              if (!updateData || updateData.length === 0) {
                console.warn(`[Worker ${workerId}] Lost lease for reminder ${rem.id} during failure recording; update discarded.`);
                continue;
              }

              failedCount++;
              results.push({
                id: rem.id,
                status: "failed",
                recipient: rem.recipient_email,
                error: errorMsg,
              });
            }
          }
        } catch (dispatchErr) {
          // Network error or timeout during fetch: Retryable failure
          const errStr = (dispatchErr as Error).message || String(dispatchErr);

          if (attemptNumber < maxAttempts) {
            const backoffMinutes = Math.min(15 * Math.pow(2, attemptNumber - 1), 60);
            const nextRetryIso = new Date(Date.now() + backoffMinutes * 60 * 1000).toISOString();

            const { data: updateData } = await supabaseAdmin
              .from("action_email_reminders")
              .update({
                status: "pending",
                is_retryable: true,
                next_retry_at: nextRetryIso,
                failure_reason: `[Attempt ${attemptNumber}/${maxAttempts} network error]: ${errStr}`,
                updated_at: new Date().toISOString(),
              })
              .eq("id", rem.id)
              .eq("claimed_by", workerId)
              .eq("status", "processing")
              .select();

            if (!updateData || updateData.length === 0) {
              console.warn(`[Worker ${workerId}] Lost lease for reminder ${rem.id} during network retry scheduling; update discarded.`);
              continue;
            }

            results.push({
              id: rem.id,
              status: "retry_scheduled",
              recipient: rem.recipient_email,
              error: `Network error (Retrying at ${nextRetryIso})`,
            });
          } else {
            const { data: updateData } = await supabaseAdmin
              .from("action_email_reminders")
              .update({
                status: "failed",
                is_retryable: false,
                next_retry_at: null,
                failure_reason: `[Max retries exceeded (${maxAttempts})]: ${errStr}`,
                updated_at: new Date().toISOString(),
              })
              .eq("id", rem.id)
              .eq("claimed_by", workerId)
              .eq("status", "processing")
              .select();

            if (!updateData || updateData.length === 0) {
              console.warn(`[Worker ${workerId}] Lost lease for reminder ${rem.id} during timeout failure recording; update discarded.`);
              continue;
            }

            failedCount++;
            results.push({
              id: rem.id,
              status: "failed",
              recipient: rem.recipient_email,
              error: errStr,
            });
          }
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          processed_count: processedCount,
          sent_count: sentCount,
          failed_count: failedCount,
          cancelled_count: cancelledCount,
          results,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({ success: false, error: `Unknown action: ${action}` }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: (error as Error).message || "Internal server error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
