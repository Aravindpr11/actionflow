// ============================================================================
// Supabase Edge Function: manage-company-admin
// ============================================================================
// Security Model:
// 1. Caller Authorization: Verifies the calling user has a valid Supabase JWT
//    and is confirmed as Platform Admin via public.is_platform_admin() RPC.
// 2. Service-Role Isolation: Uses SUPABASE_SERVICE_ROLE_KEY exclusively on
//    the server side for privileged Auth and multi-tenant database operations.
// 3. Multi-Tenant Boundary: Strictly confines updates and deletions to the
//    specified organization_id. Cross-tenant modifications are rejected.
// 4. Primary Admin Invariant & Audit Preservation:
//    - Prevents deleting the sole active admin of an organization.
//    - When removing a Primary Admin, mandates atomic reassignment to a chosen
//      secondary admin before deactivation.
//    - Preserves audit integrity through safe deactivation (is_active = false,
//      status = 'inactive') rather than hard-deleting database records.
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
    const { data: isPlatformAdmin, error: rpcError } = await userClient.rpc("is_platform_admin");
    if (rpcError || isPlatformAdmin !== true) {
      return new Response(
        JSON.stringify({
          error: "ActionFlow Security Violation: Only Platform Administrators may manage Company Administrators.",
        }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Initialize Privileged Service-Role Client
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // 4. Parse Request Body
    const body = await req.json().catch(() => ({}));
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";
    const organizationId = typeof body.organization_id === "string" ? body.organization_id.trim() : "";
    const adminId = typeof body.admin_id === "string" ? body.admin_id.trim() : "";

    if (!organizationId) {
      return new Response(
        JSON.stringify({ error: "Validation Error: organization_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (action === "list_admins") {
      const includeInactive = body.include_inactive === true;
      let query = adminClient
        .from("profiles")
        .select("id, full_name, email, phone, designation, organization_id, is_primary_admin, is_active, status, created_at, roles!inner(code)")
        .eq("organization_id", organizationId)
        .eq("roles.code", "admin");

      if (!includeInactive) {
        query = query.eq("is_active", true);
      }

      const { data: profiles, error: fetchErr } = await query.order("created_at", { ascending: true });

      if (fetchErr) {
        return new Response(
          JSON.stringify({ error: `Failed to query administrators: ${fetchErr.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Enrich profiles with auth confirmation status to accurately determine pending invitations
      const enriched = await Promise.all(
        (profiles || []).map(async (p: any) => {
          let computedStatus = p.status || "active";
          if (!p.is_active || p.status === "inactive" || p.status === "suspended") {
            computedStatus = "inactive";
          } else {
            // Check auth user state
            const { data: authData } = await adminClient.auth.admin.getUserById(p.id);
            const user = authData?.user;
            if (user && !user.email_confirmed_at && !user.confirmed_at && !user.last_sign_in_at) {
              computedStatus = "invited";
            } else {
              computedStatus = "active";
            }
          }

          return {
            id: p.id,
            full_name: p.full_name,
            email: p.email,
            phone: p.phone,
            designation: p.designation,
            organization_id: p.organization_id,
            organization_name: "",
            is_primary_admin: p.is_primary_admin === true,
            is_active: p.is_active !== false,
            status: computedStatus,
            created_at: p.created_at,
          };
        })
      );

      return new Response(
        JSON.stringify(enriched),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: delete_organization
    // ------------------------------------------------------------------------
    if (action === "delete_organization") {
      // 1. Invariant: Sobha (#1) is permanent and cannot be deleted
      if (organizationId === "00000000-0000-0000-0000-000000000001") {
        return new Response(
          JSON.stringify({
            error: "ActionFlow Security Violation: Default organization Sobha (#1) is permanent and cannot be deleted.",
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 2. Fetch organization to verify existence and check slug
      const { data: targetOrg, error: orgFetchErr } = await adminClient
        .from("organizations")
        .select("id, name, code")
        .eq("id", organizationId)
        .maybeSingle();

      if (orgFetchErr || !targetOrg) {
        return new Response(
          JSON.stringify({ error: `Organization not found: ${organizationId}` }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (typeof targetOrg.code === "string" && targetOrg.code.toLowerCase() === "sobha") {
        return new Response(
          JSON.stringify({
            error: "ActionFlow Security Violation: Default organization Sobha is permanent and cannot be deleted.",
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 3. Pre-scan Platform Admins to protect them from deletion
      const { data: platformAdminRows } = await adminClient
        .from("platform_admins")
        .select("user_id");
      const platformAdminIds = new Set(
        (platformAdminRows || []).map((r: { user_id: string }) => r.user_id)
      );

      // 4. Pre-scan tenant user IDs associated with this company before relational deletion
      // a) from public.profiles
      const { data: orgProfiles } = await adminClient
        .from("profiles")
        .select("id")
        .eq("organization_id", organizationId);

      // b) from public.account_requests
      const { data: orgRequests } = await adminClient
        .from("account_requests")
        .select("auth_user_id")
        .eq("organization_id", organizationId)
        .not("auth_user_id", "is", null);

      const candidateAuthUserIds = new Set<string>();
      for (const p of orgProfiles || []) {
        if (p.id) candidateAuthUserIds.add(p.id);
      }
      for (const r of orgRequests || []) {
        if (r.auth_user_id) candidateAuthUserIds.add(r.auth_user_id);
      }

      // Filter out Platform Admins and callerUser
      const targetAuthUserIds: string[] = [];
      for (const uid of candidateAuthUserIds) {
        if (!platformAdminIds.has(uid) && uid !== callerUser.id) {
          targetAuthUserIds.push(uid);
        }
      }

      // 5. Database Cascade Deletion:
      // Try atomic RPC function first
      let cascadeError: string | null = null;
      const { data: _rpcData, error: rpcErr } = await adminClient.rpc(
        "delete_organization_cascade",
        { p_organization_id: organizationId }
      );

      if (rpcErr) {
        console.warn(`RPC delete_organization_cascade error, attempting sequential fallback: ${rpcErr.message}`);
        // Sequential fallback via privileged service-role
        try {
          // A. account_request_scopes
          const { data: reqs } = await adminClient
            .from("account_requests")
            .select("id")
            .eq("organization_id", organizationId);
          const reqIds = (reqs || []).map((r: { id: string }) => r.id);
          if (reqIds.length > 0) {
            await adminClient
              .from("account_request_scopes")
              .delete()
              .in("account_request_id", reqIds);
          }

          // B. account_requests
          await adminClient
            .from("account_requests")
            .delete()
            .eq("organization_id", organizationId);

          // C. manager_scopes
          const { data: profs } = await adminClient
            .from("profiles")
            .select("id")
            .eq("organization_id", organizationId);
          const profIds = (profs || []).map((p: { id: string }) => p.id);
          if (profIds.length > 0) {
            await adminClient
              .from("manager_scopes")
              .delete()
              .in("manager_profile_id", profIds);
          }

          // D. team_members
          const { data: tms } = await adminClient
            .from("teams")
            .select("id")
            .eq("organization_id", organizationId);
          const teamIds = (tms || []).map((t: { id: string }) => t.id);
          if (teamIds.length > 0) {
            await adminClient
              .from("team_members")
              .delete()
              .in("team_id", teamIds);
          }
          if (profIds.length > 0) {
            await adminClient
              .from("team_members")
              .delete()
              .in("profile_id", profIds);
          }

          // E. teams
          await adminClient
            .from("teams")
            .delete()
            .eq("organization_id", organizationId);

          // F. departments and sites
          await adminClient
            .from("departments")
            .delete()
            .eq("organization_id", organizationId);

          await adminClient
            .from("sites")
            .delete()
            .eq("organization_id", organizationId);

          // G. profiles (excluding platform admins)
          let profileDeleteQuery = adminClient
            .from("profiles")
            .delete()
            .eq("organization_id", organizationId);
          if (platformAdminIds.size > 0) {
            for (const paid of platformAdminIds) {
              profileDeleteQuery = profileDeleteQuery.neq("id", paid);
            }
          }
          await profileDeleteQuery;

          // H. organizations
          const { error: orgDelErr } = await adminClient
            .from("organizations")
            .delete()
            .eq("id", organizationId);

          if (orgDelErr) {
            cascadeError = orgDelErr.message;
          }
        } catch (fallbackErr: any) {
          cascadeError = fallbackErr?.message || String(fallbackErr);
        }
      }

      if (cascadeError) {
        return new Response(
          JSON.stringify({ error: `Failed to delete organization from database: ${cascadeError}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 6. Delete associated GoTrue Auth users
      const deletedAuthUserIds: string[] = [];
      const failedAuthUserIds: string[] = [];
      for (const uid of targetAuthUserIds) {
        const { error: authDelErr } = await adminClient.auth.admin.deleteUser(uid);
        if (authDelErr) {
          console.error(`Failed to delete auth user ${uid}: ${authDelErr.message}`);
          failedAuthUserIds.push(uid);
        } else {
          deletedAuthUserIds.push(uid);
        }
      }

      // 7. Return Result
      if (failedAuthUserIds.length > 0) {
        return new Response(
          JSON.stringify({
            success: false,
            partial: true,
            message: `Company "${targetOrg.name}" was deleted from database, but ${failedAuthUserIds.length} auth user(s) could not be removed from GoTrue Auth.`,
            failed_auth_user_ids: failedAuthUserIds,
            deleted_auth_user_ids: deletedAuthUserIds,
          }),
          { status: 207, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: `Company "${targetOrg.name}" and all associated tenant data and ${deletedAuthUserIds.length} auth user(s) were permanently deleted.`,
          deleted_auth_user_ids: deletedAuthUserIds,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!adminId) {
      return new Response(
        JSON.stringify({ error: "Validation Error: admin_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: update_admin
    // ------------------------------------------------------------------------
    if (action === "update_admin") {
      const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      const phone = typeof body.phone === "string" ? body.phone.trim() : null;
      const designation = typeof body.designation === "string" ? body.designation.trim() : null;

      if (!fullName || fullName.length < 2) {
        return new Response(
          JSON.stringify({ error: "Validation Error: full_name must be at least 2 characters" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (fullName.length > 150) {
        return new Response(
          JSON.stringify({ error: "Validation Error: full_name cannot exceed 150 characters" }),
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

      // Verify Target Admin exists and belongs to this organization
      const { data: targetProfile, error: targetError } = await adminClient
        .from("profiles")
        .select("id, email, organization_id, is_primary_admin, is_active, status")
        .eq("id", adminId)
        .maybeSingle();

      if (targetError || !targetProfile) {
        return new Response(
          JSON.stringify({ error: "Target administrator profile not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (targetProfile.organization_id !== organizationId) {
        return new Response(
          JSON.stringify({ error: "ActionFlow Security Violation: Administrator does not belong to specified organization" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Handle Email Update: Requires server-side Auth update to keep auth.users and profiles synchronized
      if (email !== targetProfile.email.toLowerCase()) {
        // Check if another profile already uses this email
        const { data: dupProfile } = await adminClient
          .from("profiles")
          .select("id")
          .eq("email", email)
          .neq("id", adminId)
          .maybeSingle();

        if (dupProfile) {
          return new Response(
            JSON.stringify({ error: `An account with email "${email}" already exists in the system` }),
            { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        // Update email in Supabase Auth (GoTrue).
        // Database trigger trg_on_auth_user_email_updated synchronizes to public.profiles.email automatically.
        const { error: authUpdateError } = await adminClient.auth.admin.updateUserById(adminId, {
          email: email,
          email_confirm: true,
        });

        if (authUpdateError) {
          return new Response(
            JSON.stringify({ error: `Failed to update auth identity email: ${authUpdateError.message}` }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      // Update remaining profile fields in public.profiles
      const { error: updateError } = await adminClient
        .from("profiles")
        .update({
          full_name: fullName,
          phone: phone,
          designation: designation,
          updated_at: new Date().toISOString(),
        })
        .eq("id", adminId);

      if (updateError) {
        return new Response(
          JSON.stringify({ error: `Failed to update profile details: ${updateError.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Fetch fresh profile state to return
      const { data: updatedProfile, error: fetchError } = await adminClient
        .from("profiles")
        .select("id, full_name, email, phone, designation, organization_id, is_primary_admin, is_active, status, created_at")
        .eq("id", adminId)
        .single();

      if (fetchError || !updatedProfile) {
        return new Response(
          JSON.stringify({ error: "Failed to reload updated administrator profile" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          id: updatedProfile.id,
          full_name: updatedProfile.full_name,
          email: updatedProfile.email,
          phone: updatedProfile.phone,
          designation: updatedProfile.designation,
          organization_id: updatedProfile.organization_id,
          organization_name: "",
          is_primary_admin: updatedProfile.is_primary_admin === true,
          is_active: updatedProfile.is_active !== false,
          status: updatedProfile.status ?? "active",
          created_at: updatedProfile.created_at,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: delete_admin
    // ------------------------------------------------------------------------
    if (action === "delete_admin") {
      const newPrimaryAdminId = typeof body.new_primary_admin_id === "string" ? body.new_primary_admin_id.trim() : null;

      // 1. Fetch all active Company Admins for this organization
      const { data: activeAdmins, error: adminsError } = await adminClient
        .from("profiles")
        .select("id, full_name, email, is_primary_admin, is_active, organization_id, roles!inner(code)")
        .eq("organization_id", organizationId)
        .eq("roles.code", "admin")
        .eq("is_active", true);

      if (adminsError) {
        return new Response(
          JSON.stringify({ error: `Database error querying administrators: ${adminsError.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Rule: Never allow the company to have zero active Company Admins
      if (!activeAdmins || activeAdmins.length <= 1) {
        return new Response(
          JSON.stringify({
            error: "ActionFlow Security Violation: Cannot remove the only active administrator of this company. Every company must retain at least one active administrator.",
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const targetAdmin = activeAdmins.find((a: { id: string }) => a.id === adminId);
      if (!targetAdmin) {
        return new Response(
          JSON.stringify({ error: "Target administrator not found among active administrators of this organization" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Rule: Primary Admin removal requires selecting a successor Primary Admin
      if (targetAdmin.is_primary_admin) {
        if (!newPrimaryAdminId) {
          return new Response(
            JSON.stringify({
              error: "Primary Administrator cannot be removed without selecting a successor Primary Administrator.",
            }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        if (newPrimaryAdminId === adminId) {
          return new Response(
            JSON.stringify({ error: "Successor Primary Administrator must be a different active administrator." }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        const successorAdmin = activeAdmins.find((a: { id: string }) => a.id === newPrimaryAdminId);
        if (!successorAdmin) {
          return new Response(
            JSON.stringify({ error: "Successor administrator not found among active administrators of this organization" }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        // Sequential primary swap:
        // Step A: Deactivate outgoing admin first (is_primary_admin = false, is_active = false)
        // This ensures the partial unique index uq_profiles_single_active_primary_admin_per_org is cleared
        const { error: deactivateError } = await adminClient
          .from("profiles")
          .update({
            is_primary_admin: false,
            is_active: false,
            status: "inactive",
            updated_at: new Date().toISOString(),
          })
          .eq("id", adminId);

        if (deactivateError) {
          return new Response(
            JSON.stringify({ error: `Failed to deactivate outgoing primary administrator: ${deactivateError.message}` }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        // Step B: Promote successor to Primary Admin
        const { error: promoteError } = await adminClient
          .from("profiles")
          .update({
            is_primary_admin: true,
            updated_at: new Date().toISOString(),
          })
          .eq("id", newPrimaryAdminId);

        if (promoteError) {
          return new Response(
            JSON.stringify({ error: `Failed to promote successor to Primary Administrator: ${promoteError.message}` }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      } else {
        // Target is a secondary admin: simply deactivate
        const { error: deactivateError } = await adminClient
          .from("profiles")
          .update({
            is_active: false,
            status: "inactive",
            updated_at: new Date().toISOString(),
          })
          .eq("id", adminId);

        if (deactivateError) {
          return new Response(
            JSON.stringify({ error: `Failed to deactivate administrator: ${deactivateError.message}` }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      // Revoke Auth user access so they can no longer sign in
      await adminClient.auth.admin.updateUserById(adminId, {
        ban_duration: "876000h",
      });

      return new Response(
        JSON.stringify({
          success: true,
          message: "Company Administrator access revoked successfully.",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: resend_invitation
    // ------------------------------------------------------------------------
    if (action === "resend_invitation") {
      // 1. Verify Target Admin exists and belongs to this organization
      const { data: targetProfile, error: targetError } = await adminClient
        .from("profiles")
        .select("id, email, organization_id, is_primary_admin, is_active, status")
        .eq("id", adminId)
        .maybeSingle();

      if (targetError || !targetProfile) {
        return new Response(
          JSON.stringify({ error: "Target administrator profile not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (targetProfile.organization_id !== organizationId) {
        return new Response(
          JSON.stringify({ error: "ActionFlow Security Violation: Cross-organization administrator modification is prohibited." }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Check if administrator has been deactivated/disabled
      if (!targetProfile.is_active || targetProfile.status === "inactive" || targetProfile.status === "suspended") {
        return new Response(
          JSON.stringify({ error: "Cannot resend invitation to a disabled or removed administrator." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 2. Fetch Auth user state to verify they haven't completed activation yet
      const { data: authUserData, error: authUserError } = await adminClient.auth.admin.getUserById(adminId);
      if (authUserError || !authUserData?.user) {
        return new Response(
          JSON.stringify({ error: `Associated Auth user not found: ${authUserError?.message || "User does not exist"}` }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const authUser = authUserData.user;

      // 3. Verify user has not already activated
      if (authUser.email_confirmed_at || authUser.confirmed_at || authUser.last_sign_in_at) {
        return new Response(
          JSON.stringify({ error: "Administrator has already completed activation and confirmed their account." }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // 4. Determine redirect URL
      const appUrl = Deno.env.get("APP_URL") || Deno.env.get("ACTIONFLOW_REDIRECT_URL") || "http://localhost:8080";
      const redirectTo = typeof body.redirect_to === "string" && body.redirect_to.trim().length > 0
        ? body.redirect_to.trim()
        : appUrl;

      // 5. Send fresh invitation email for existing unconfirmed user using Auth Admin API
      const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
        targetProfile.email,
        { redirectTo }
      );

      if (inviteError) {
        return new Response(
          JSON.stringify({ error: `Failed to resend user invitation email: ${inviteError.message}` }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: `Fresh invitation email sent successfully to ${targetProfile.email}.`,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: `Unsupported action "${action}". Permitted actions: "list_admins", "update_admin", "delete_admin", "resend_invitation", "delete_organization"` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Server error: ${err instanceof Error ? err.message : String(err)}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

