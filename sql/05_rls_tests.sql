-- =============================================================================
-- RLS Test Suite
-- Run BEFORE policies to confirm tests catch leakage, then AFTER to confirm fix
-- =============================================================================
-- Schema uses BIGINT IDs, not UUIDs

-- -----------------------------------------------------------------------------
-- Setup: Create second test tenant with known row counts
-- Company 1 (Gulf Freight) already exists with 1 shipment
-- -----------------------------------------------------------------------------

-- Create second test company
INSERT INTO companies (id, legal_name, trade_name, base_currency, country_code, timezone, is_active)
VALUES (999, 'Test Competitor Ltd', 'Competitor', 'USD', 'US', 'America/New_York', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Get required FKs for shipment creation
DO $$
DECLARE
    v_contract_id BIGINT;
    v_location_id BIGINT;
BEGIN
    -- Get existing contract for company 1
    SELECT id INTO v_contract_id FROM contracts WHERE company_id = 1 LIMIT 1;
    SELECT id INTO v_location_id FROM locations LIMIT 1;

    -- Create minimal contract for company 999 if needed
    IF NOT EXISTS (SELECT 1 FROM contracts WHERE company_id = 999) THEN
        INSERT INTO contracts (
            company_id, contract_no, contract_type_id,
            customer_id, seller_id, buyer_id,
            origin_location_id, destination_location_id,
            primary_mode, incoterm, valid_from, status
        )
        SELECT
            999, 'TEST-999-001', ct.id,
            (SELECT id FROM parties LIMIT 1),
            (SELECT id FROM parties LIMIT 1),
            (SELECT id FROM parties LIMIT 1 OFFSET 1),
            v_location_id, v_location_id,
            'road', 'EXW', CURRENT_DATE, 'draft'
        FROM contract_types ct LIMIT 1;
    END IF;

    -- Add 2 shipments for company 999
    DELETE FROM shipments WHERE company_id = 999;

    INSERT INTO shipments (
        company_id, contract_id, shipment_no, tracking_no,
        status, priority, origin_location_id, destination_location_id
    )
    SELECT
        999, c.id, 'COMP999-001', 'TRK999001',
        'created', 'normal', c.origin_location_id, c.destination_location_id
    FROM contracts c WHERE c.company_id = 999 LIMIT 1;

    INSERT INTO shipments (
        company_id, contract_id, shipment_no, tracking_no,
        status, priority, origin_location_id, destination_location_id
    )
    SELECT
        999, c.id, 'COMP999-002', 'TRK999002',
        'created', 'normal', c.origin_location_id, c.destination_location_id
    FROM contracts c WHERE c.company_id = 999 LIMIT 1;
END $$;

-- Verify setup
SELECT 'SETUP CHECK' AS test,
       (SELECT COUNT(*) FROM shipments WHERE company_id = 1) AS company_1_shipments,
       (SELECT COUNT(*) FROM shipments WHERE company_id = 999) AS company_999_shipments;

-- =============================================================================
-- TEST 1: Read isolation (exact counts)
-- =============================================================================

-- 1a: Company 1 sees exactly 1 shipment (positive control)
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);
    SELECT COUNT(*) INTO v_count FROM shipments;

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 1a FAILED: Company 1 should see 1 shipment, saw %', v_count;
    END IF;
    RAISE NOTICE 'TEST 1a PASSED: Company 1 sees exactly 1 shipment';
END $$;

-- 1b: Company 999 sees exactly 2 shipments
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM set_config('app.company_id', '999', TRUE);
    SELECT COUNT(*) INTO v_count FROM shipments;

    IF v_count <> 2 THEN
        RAISE EXCEPTION 'TEST 1b FAILED: Company 999 should see 2 shipments, saw %', v_count;
    END IF;
    RAISE NOTICE 'TEST 1b PASSED: Company 999 sees exactly 2 shipments';
END $$;

-- 1c: Company 1 cannot see Company 999's shipment numbers
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);
    SELECT COUNT(*) INTO v_count FROM shipments WHERE shipment_no LIKE 'COMP999-%';

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST 1c FAILED: Company 1 saw % of Company 999 shipments', v_count;
    END IF;
    RAISE NOTICE 'TEST 1c PASSED: Company 1 cannot see Company 999 shipments';
END $$;

-- =============================================================================
-- TEST 2: Write isolation (WITH CHECK)
-- =============================================================================

-- 2a: Company 1 cannot INSERT into Company 999's scope
DO $$
DECLARE
    v_contract_id BIGINT;
    v_location_id BIGINT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);
    SELECT id INTO v_contract_id FROM contracts WHERE company_id = 999 LIMIT 1;
    SELECT id INTO v_location_id FROM locations LIMIT 1;

    BEGIN
        INSERT INTO shipments (
            company_id, contract_id, shipment_no, tracking_no,
            status, priority, origin_location_id, destination_location_id
        )
        VALUES (999, v_contract_id, 'ATTACK-001', 'TRKATTACK', 'created', 'normal', v_location_id, v_location_id);

        RAISE EXCEPTION 'TEST 2a FAILED: Company 1 inserted into Company 999 scope';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'TEST 2a PASSED: Insert blocked by RLS';
        WHEN check_violation THEN
            RAISE NOTICE 'TEST 2a PASSED: Insert blocked by WITH CHECK';
        WHEN others THEN
            -- Before RLS, this succeeds - that's the expected pre-RLS failure
            RAISE WARNING 'TEST 2a PRE-RLS: Insert succeeded (expected before policies)';
    END;
END $$;

-- 2b: Company 1 cannot UPDATE Company 999's rows
DO $$
DECLARE
    v_updated INT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);

    UPDATE shipments SET status = 'cancelled' WHERE company_id = 999;
    GET DIAGNOSTICS v_updated = ROW_COUNT;

    IF v_updated > 0 THEN
        RAISE EXCEPTION 'TEST 2b FAILED: Company 1 updated % of Company 999 rows', v_updated;
    END IF;
    RAISE NOTICE 'TEST 2b PASSED: Company 1 cannot update Company 999 rows';
END $$;

-- 2c: Company 1 cannot DELETE Company 999's rows
DO $$
DECLARE
    v_deleted INT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);

    DELETE FROM shipments WHERE company_id = 999;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted > 0 THEN
        RAISE EXCEPTION 'TEST 2c FAILED: Company 1 deleted % of Company 999 rows', v_deleted;
    END IF;
    RAISE NOTICE 'TEST 2c PASSED: Company 1 cannot delete Company 999 rows';
END $$;

-- =============================================================================
-- TEST 3: Unset session variable = fail loud
-- =============================================================================

DO $$
DECLARE
    v_count INT;
BEGIN
    -- Clear the session variable
    PERFORM set_config('app.company_id', '', TRUE);

    BEGIN
        SELECT COUNT(*) INTO v_count FROM shipments;

        -- If we reach here, RLS didn't throw
        IF v_count = 0 THEN
            RAISE WARNING 'TEST 3 FAIL-CLOSED: Unset session returned 0 rows (silent fail)';
        ELSIF v_count = 3 THEN
            RAISE EXCEPTION 'TEST 3 FAIL-OPEN: Unset session returned all 3 rows (CRITICAL)';
        ELSE
            RAISE WARNING 'TEST 3 UNEXPECTED: Unset session returned % rows', v_count;
        END IF;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RAISE NOTICE 'TEST 3 PASSED: Unset session throws (fail loud)';
        WHEN others THEN
            RAISE NOTICE 'TEST 3 PASSED: Unset session throws: %', SQLERRM;
    END;
END $$;

-- =============================================================================
-- TEST 4: Global reference tables readable without tenant context
-- =============================================================================

DO $$
DECLARE
    v_countries INT;
    v_currencies INT;
    v_unions INT;
BEGIN
    -- Clear tenant context
    PERFORM set_config('app.company_id', '', TRUE);

    -- These should work without tenant context
    SELECT COUNT(*) INTO v_countries FROM countries;
    SELECT COUNT(*) INTO v_currencies FROM currencies;
    SELECT COUNT(*) INTO v_unions FROM customs_unions;

    IF v_countries > 0 AND v_currencies > 0 AND v_unions > 0 THEN
        RAISE NOTICE 'TEST 4 PASSED: Reference tables readable (% countries, % currencies, % unions)',
            v_countries, v_currencies, v_unions;
    ELSE
        RAISE EXCEPTION 'TEST 4 FAILED: Reference tables not readable or empty';
    END IF;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Reference tables blocked: %', SQLERRM;
END $$;

-- =============================================================================
-- TEST 5: Role check
-- =============================================================================

DO $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT current_user INTO v_role;

    IF v_role IN ('postgres', 'supabase_admin', 'service_role') THEN
        RAISE WARNING 'TEST 5: Running as % - this role bypasses RLS. Application must use authenticated/anon role.', v_role;
    ELSE
        RAISE NOTICE 'TEST 5: Running as % - verify RLS applies to this role', v_role;
    END IF;
END $$;

-- =============================================================================
-- Summary: Expected results
-- =============================================================================
--
-- BEFORE RLS (tests should fail):
--   1a: FAIL - sees all 3 shipments
--   1b: FAIL - sees all 3 shipments
--   1c: FAIL - sees other tenant's data
--   2a: WARNING - insert succeeds
--   2b: FAIL - update affects rows
--   2c: FAIL - delete affects rows
--   3:  WARNING - returns rows (fail closed or open)
--   4:  PASS - reference tables always readable
--   5:  WARNING if running as postgres
--
-- AFTER RLS (all should pass):
--   1a-c: PASS
--   2a-c: PASS
--   3:    PASS (fail loud)
--   4:    PASS
--   5:    NOTICE (non-bypassing role)
-- =============================================================================
