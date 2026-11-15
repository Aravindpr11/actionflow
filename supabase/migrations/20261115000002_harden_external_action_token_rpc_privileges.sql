-- Migration: 20261115000002_harden_external_action_token_rpc_privileges.sql
-- Description: Revoke EXECUTE from PUBLIC/anon on create_or_get_external_action_token RPC to prevent unauthenticated token generation.

REVOKE EXECUTE ON FUNCTION public.create_or_get_external_action_token(uuid, character varying, integer, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_or_get_external_action_token(uuid, character varying, integer, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_or_get_external_action_token(uuid, character varying, integer, uuid) TO authenticated, service_role;
