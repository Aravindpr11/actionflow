// ============================================================================
// Supabase Edge Function: invite-company-admin
// ============================================================================
// Security Model:
// 1. Caller Authorization: Verifies the calling user has a valid Supabase JWT
//    and is explicitly listed in public.platform_admins (Tier 0 authority).
// 2. Service-Role Isolation: Uses SUPABASE_SERVICE_ROLE_KEY exclusively within
//    this server-side Edge Function. The key is NEVER exposed to the client.
// 3. Multi-Tenant Enforcement: Binds the invited Company Admin strictly to the
//    specified organization_id. Validates that the organization exists and is active.
// 4. Primary Admin Invariant: Dynamically determines if an active primary admin
//    already exists for the organization; sets is_primary_admin accordingly.
// 5. Atomic Rollback: Deletes the created auth user if profile insertion fails.
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration error: Missing required environment variables" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Verify Caller Authentication (JWT)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace(/^Bearer\s+/i, "");

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user: callerUser },
      error: callerError,
    } = await userClient.auth.getUser(token);

    if (callerError || !callerUser) {
      return new Response(
        JSON.stringify({ error: "Unauthorized: Invalid or expired session token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Verify Caller is Platform Admin via Canonical Database Helper
    // The SECURITY DEFINER function public.is_platform_admin() executes with database
    // owner privileges using the caller's authenticated session (auth.uid()), which
    // avoids PostgREST RLS recursion and permission limitations on public.platform_admins.
    const { data: rpcResult, error: rpcError } = await userClient.rpc("is_platform_admin");

    if (rpcError || rpcResult !== true) {
      console.error("[invite-company-admin] Platform admin authorization failed:", {
        callerUserId: callerUser.id,
        callerEmail: callerUser.email,
        rpcResult,
        rpcError: rpcError?.message,
      });

      return new Response(
        JSON.stringify({
          error: `ActionFlow Security Violation: Only Platform Administrators may invite Company Administrators. [diag: callerId=${callerUser.id}, rpcResult=${rpcResult}, rpcError=${rpcError?.message ?? "none"}]`,
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Initialize Service-Role Client for Organization Validation & User Provisioning
    // Used exclusively for administrative operations after authorization succeeds.
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // 4. Parse & Validate Request Body
    const body = await req.json().catch(() => ({}));
    const organizationId = typeof body.organization_id === "string" ? body.organization_id.trim() : "";
    const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const phone = typeof body.phone === "string" ? body.phone.trim() : null;
    const designation = typeof body.designation === "string" ? body.designation.trim() : "Company Administrator";

    if (!organizationId) {
      return new Response(
        JSON.stringify({ error: "Validation Error: organization_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!fullName || fullName.length < 2) {
      return new Response(
        JSON.stringify({ error: "Validation Error: full_name must be at least 2 characters" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const emailRegex = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/;
    if (!email || !emailRegex.test(email)) {
      return new Response(
        JSON.stringify({ error: "Validation Error: A valid email address is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 5. Verify Target Organization Exists and is Active
    const { data: orgRecord, error: orgError } = await adminClient
      .from("organizations")
      .select("id, name, is_active")
      .eq("id", organizationId)
      .maybeSingle();

    if (orgError) {
      return new Response(
        JSON.stringify({ error: `Database error querying organization: ${orgError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!orgRecord) {
      return new Response(
        JSON.stringify({ error: `Target organization not found with ID "${organizationId}"` }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!orgRecord.is_active) {
      return new Response(
        JSON.stringify({ error: "Target organization is currently inactive" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 6. Prevent Duplicate Accounts with Identical Email
    const { data: existingProfile } = await adminClient
      .from("profiles")
      .select("id, email, organization_id")
      .eq("email", email)
      .maybeSingle();

    if (existingProfile) {
      return new Response(
        JSON.stringify({ error: `An account with email "${email}" already exists in the system` }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 7. Look Up Internal Admin Role ID
    const { data: adminRole, error: roleError } = await adminClient
      .from("roles")
      .select("id")
      .eq("code", "admin")
      .single();

    if (roleError || !adminRole) {
      return new Response(
        JSON.stringify({ error: "Database configuration error: Admin role definition not found" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 8. Check Single Primary Admin Invariant for Target Organization
    const { count: activePrimaryCount, error: countError } = await adminClient
      .from("profiles")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("is_primary_admin", true)
      .eq("is_active", true);

    if (countError) {
      return new Response(
        JSON.stringify({ error: `Database error checking primary admin status: ${countError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // If company currently has no active primary admin, this user is designated primary admin
    const isPrimaryAdmin = (activePrimaryCount ?? 0) === 0;

    // 9. Issue Supabase Auth Invitation (Sends email with secure activation link)
    // Note: Invoked without custom user metadata so that handle_new_auth_user()
    // safely bypasses account_requests generation. The authoritative profile row
    // is provisioned explicitly in step 10 below.
    const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
      email,
      { redirectTo: "http://localhost:8080" }
    );

    if (inviteError || !inviteData?.user) {
      return new Response(
        JSON.stringify({ error: `Failed to issue user invitation: ${inviteError?.message || "Unknown auth error"}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const newAuthUserId = inviteData.user.id;

    // 10. Provision public.profiles Row Bound to Organization
    const { error: profileError } = await adminClient
      .from("profiles")
      .insert({
        id: newAuthUserId,
        full_name: fullName,
        email: email,
        phone: phone,
        designation: designation,
        role_id: adminRole.id,
        organization_id: organizationId,
        is_primary_admin: isPrimaryAdmin,
        status: "active",
        is_active: true,
      });

    if (profileError) {
      // Compensating action: Delete the created Auth user if profile provisioning fails
      await adminClient.auth.admin.deleteUser(newAuthUserId);
      return new Response(
        JSON.stringify({ error: `Failed to create profile row: ${profileError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 11. Return Success Payload (Matching CompanyAdminSummary schema)
    return new Response(
      JSON.stringify({
        id: newAuthUserId,
        full_name: fullName,
        email: email,
        phone: phone,
        designation: designation,
        organization_id: organizationId,
        organization_name: orgRecord.name,
        is_primary_admin: isPrimaryAdmin,
        status: "active",
        is_active: true,
        created_at: new Date().toISOString(),
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: `Unexpected server error: ${message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

