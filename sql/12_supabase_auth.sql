-- =============================================================================
-- 12_supabase_auth.sql
-- Supabase/PostgREST authentication integration
--
-- Problem: current_company_id() reads session variable, but PostgREST uses
-- connection pooling and identifies callers via JWT, not session variables.
-- Every query through Supabase would fail with "app.company_id is not set".
--
-- Solution: Read JWT claims first, fall back to session variable for direct
-- connections (psql, tests, migrations).
--
-- Run after 11_ownership_resolution.sql
-- =============================================================================

-- =============================================================================
-- PART 1: USER PROFILES MAPPING
-- =============================================================================
-- Links Supabase auth.users to the schema's users table and company_id.
-- This is the source of truth for JWT claims.
--
-- Note: auth.users only exists in Supabase. For local testing without Supabase,
-- the FK constraint is omitted. In production, add:
--   ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_auth_fk
--   FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS user_profiles (
    id              UUID PRIMARY KEY,  -- References auth.users(id) in Supabase
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id      BIGINT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id)  -- one profile per schema user
);

-- Add FK to auth.users if the auth schema exists (Supabase environment)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_auth_fk;
        ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_auth_fk
            FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_user_profiles_company ON user_profiles(company_id);

COMMENT ON TABLE user_profiles IS
'Maps Supabase auth.users to schema users and companies.
Used by custom access token hook to include company_id and user_id in JWT.';

-- =============================================================================
-- PART 2: UPDATED TENANT CONTEXT FUNCTION
-- =============================================================================
-- Reads JWT first (Supabase/PostgREST path), falls back to session variable
-- (direct psql/test path). Existing test suite continues to work.

CREATE OR REPLACE FUNCTION current_company_id()
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $cc$
DECLARE
    v TEXT;
    claims json;
BEGIN
    -- Supabase / PostgREST path: read from JWT claims
    BEGIN
        claims := nullif(current_setting('request.jwt.claims', true), '')::json;
        IF claims IS NOT NULL THEN
            -- Try top-level first (our hook writes here)
            v := claims ->> 'company_id';
            -- Fall back to app_metadata (some Supabase versions nest here)
            IF v IS NULL THEN
                v := claims -> 'app_metadata' ->> 'company_id';
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v := NULL;  -- JSON parse failed, try session variable
    END;

    -- Direct connection path: psql, tests, migrations
    IF v IS NULL THEN
        v := nullif(current_setting('app.company_id', true), '');
    END IF;

    -- Fail loud if neither is set
    IF v IS NULL THEN
        RAISE EXCEPTION 'No tenant context: neither JWT claim nor app.company_id is set'
            USING HINT = 'Set app.company_id for direct connections, or ensure JWT contains company_id claim.';
    END IF;

    RETURN v::BIGINT;
END;
$cc$;

COMMENT ON FUNCTION current_company_id() IS
'Returns current tenant ID from JWT claim (Supabase) or session variable (direct connection).
Fails loud if neither is set. Used by all RLS policies.';

-- =============================================================================
-- PART 3: USER ID FUNCTION
-- =============================================================================
-- Same pattern for user_id, needed by audit triggers.

CREATE OR REPLACE FUNCTION current_user_id()
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $cu$
DECLARE
    v TEXT;
    claims json;
BEGIN
    -- Supabase / PostgREST path: read from JWT claims
    BEGIN
        claims := nullif(current_setting('request.jwt.claims', true), '')::json;
        IF claims IS NOT NULL THEN
            -- Try top-level first (our hook writes here)
            v := claims ->> 'user_id';
            -- Fall back to app_metadata (some Supabase versions nest here)
            IF v IS NULL THEN
                v := claims -> 'app_metadata' ->> 'user_id';
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v := NULL;
    END;

    -- Direct connection path
    IF v IS NULL THEN
        v := nullif(current_setting('app.current_user_id', true), '');
    END IF;

    -- NULL is acceptable for user_id (anonymous/system operations)
    IF v IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN v::BIGINT;
END;
$cu$;

COMMENT ON FUNCTION current_user_id() IS
'Returns current user ID from JWT claim (Supabase) or session variable (direct connection).
Returns NULL if not set (acceptable for system operations). Used by audit triggers.';

-- =============================================================================
-- PART 4: UPDATE TASK STATUS AUDIT TRIGGER
-- =============================================================================
-- Use the new current_user_id() function instead of direct session variable read.

CREATE OR REPLACE FUNCTION fn_log_task_status() RETURNS TRIGGER AS $fn$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO task_status_history (task_id, from_status, to_status, changed_by, reason)
        VALUES (NEW.id, OLD.status, NEW.status,
                current_user_id(),  -- now reads JWT or session variable
                NEW.hold_reason);
    END IF;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_log_task_status() IS
'Logs task status changes to task_status_history.
Uses current_user_id() which reads from JWT claim or session variable.';

-- =============================================================================
-- PART 5: CUSTOM ACCESS TOKEN HOOK
-- =============================================================================
-- Supabase calls this function to add custom claims to the JWT.
-- Must be created in the supabase_functions schema or configured in dashboard.
--
-- Note: This function signature is specific to Supabase's auth hook system.
-- See: https://supabase.com/docs/guides/auth/auth-hooks

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $hook$
DECLARE
    claims jsonb;
    v_company_id BIGINT;
    v_user_id BIGINT;
BEGIN
    claims := event -> 'claims';

    -- Lookup must not error - missing profile returns original claims unchanged
    -- If this throws, Supabase issues token without custom claims (silent failure)
    BEGIN
        SELECT company_id, user_id INTO v_company_id, v_user_id
        FROM user_profiles
        WHERE id = (event ->> 'user_id')::uuid;

        IF v_company_id IS NOT NULL THEN
            claims := jsonb_set(claims, '{company_id}', to_jsonb(v_company_id));
            claims := jsonb_set(claims, '{user_id}', to_jsonb(v_user_id));
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- Return original claims on any error
        NULL;
    END;

    RETURN jsonb_set(event, '{claims}', claims);
END;
$hook$;

COMMENT ON FUNCTION custom_access_token_hook(jsonb) IS
'Supabase auth hook that adds company_id and user_id to JWT claims.
Must be registered in Supabase dashboard under Authentication > Hooks.';

-- Grant execute to supabase_auth_admin (the role Supabase uses for auth hooks)
-- CRITICAL: Without these grants, the hook silently returns default claims
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
        GRANT SELECT ON user_profiles TO supabase_auth_admin;
        GRANT EXECUTE ON FUNCTION custom_access_token_hook(jsonb) TO supabase_auth_admin;
    END IF;
END $$;

-- =============================================================================
-- PART 6: RLS FOR USER_PROFILES
-- =============================================================================
-- Users can only see/modify their own profile.
-- Note: auth.uid() only exists in Supabase. Policies created conditionally.

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles FORCE ROW LEVEL SECURITY;

-- Create policy only if auth schema exists (Supabase environment)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.routines
               WHERE routine_schema = 'auth' AND routine_name = 'uid') THEN
        -- Users can read their own profile
        DROP POLICY IF EXISTS user_profiles_select ON user_profiles;
        CREATE POLICY user_profiles_select ON user_profiles
            FOR SELECT USING (id = auth.uid());
    ELSE
        -- Local testing: allow all reads (RLS still enforces no writes)
        DROP POLICY IF EXISTS user_profiles_select ON user_profiles;
        CREATE POLICY user_profiles_select ON user_profiles
            FOR SELECT USING (true);
    END IF;
END $$;

-- Only service role can insert/update profiles (done during onboarding)
-- No INSERT/UPDATE policy for authenticated = blocked

-- =============================================================================
-- PART 7: GRANT ACCESS
-- =============================================================================

-- Grant to authenticated role if it exists (Supabase environment)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION current_company_id() TO authenticated;
        GRANT EXECUTE ON FUNCTION current_user_id() TO authenticated;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT ALL ON user_profiles TO service_role;
    END IF;
END $$;
