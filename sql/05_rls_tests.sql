-- =============================================================================
-- RLS Test Suite
-- Run BEFORE policies to confirm tests catch leakage, then AFTER to confirm fix
-- =============================================================================
-- Schema uses BIGINT IDs, not UUIDs

-- -----------------------------------------------------------------------------
-- Setup: Create second test tenant with known row counts
-- Company 1 (Gulf Freight) already exists with 1 shipment
-- IMPORTANT: Reset to superuser for setup, RLS policies don't apply to superuser
-- -----------------------------------------------------------------------------

RESET ROLE;

-- Create second test company
INSERT INTO companies (id, legal_name, trade_name, base_currency, country_code, timezone, is_active)
VALUES (999, 'Test Competitor Ltd', 'Competitor', 'USD', 'US', 'America/New_York', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Get required FKs for shipment creation
DO $$
DECLARE
    v_contract_id BIGINT;
    v_origin_id BIGINT;
    v_dest_id BIGINT;
BEGIN
    -- Get existing contract for company 1
    SELECT id INTO v_contract_id FROM contracts WHERE company_id = 1 LIMIT 1;
    SELECT id INTO v_origin_id FROM locations ORDER BY id LIMIT 1;
    SELECT id INTO v_dest_id FROM locations ORDER BY id LIMIT 1 OFFSET 1;

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
            v_origin_id, v_dest_id,
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

-- Verify setup (still as superuser)
SELECT 'SETUP CHECK' AS test,
       (SELECT COUNT(*) FROM shipments WHERE company_id = 1) AS company_1_shipments,
       (SELECT COUNT(*) FROM shipments WHERE company_id = 999) AS company_999_shipments;

-- Switch to authenticated role for actual RLS testing
SET ROLE authenticated;

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
-- TEST 6: Usage metering tests
-- =============================================================================
-- Setup: Create subscriptions and tasks for metering tests (as superuser)

RESET ROLE;

DO $$
DECLARE
    v_shipment_id BIGINT;
    v_stage_id BIGINT;
    v_plan_id BIGINT;
BEGIN
    -- Get a plan
    SELECT id INTO v_plan_id FROM billing_plans WHERE code = 'BUSINESS' LIMIT 1;

    -- Create subscription for company 1 (with active subscription)
    DELETE FROM usage_events WHERE company_id IN (1, 999);
    DELETE FROM company_subscriptions WHERE company_id IN (1, 999);

    INSERT INTO company_subscriptions (
        company_id, plan_id, status,
        started_on, current_period_start, current_period_end
    ) VALUES (
        1, v_plan_id, 'active',
        CURRENT_DATE, CURRENT_DATE, CURRENT_DATE + 30
    );

    -- Company 999 has NO subscription (for test 6b)

    -- Get shipment and stage for task creation
    SELECT id INTO v_shipment_id FROM shipments WHERE company_id = 1 LIMIT 1;

    IF v_shipment_id IS NOT NULL THEN
        -- Ensure a stage exists
        INSERT INTO shipment_stages (shipment_id, sequence_no, code, name, status)
        SELECT v_shipment_id, 99, 'TEST_STAGE', 'Test Stage', 'active'
        WHERE NOT EXISTS (
            SELECT 1 FROM shipment_stages WHERE shipment_id = v_shipment_id AND code = 'TEST_STAGE'
        );

        SELECT id INTO v_stage_id FROM shipment_stages
        WHERE shipment_id = v_shipment_id AND code = 'TEST_STAGE';

        -- Create a test task for company 1 (metering test)
        -- Use status='created' to satisfy tasks_assignment_rule, then update to in_progress
        DELETE FROM tasks WHERE task_no = 'METER-TEST-001';
        INSERT INTO tasks (
            company_id, shipment_id, stage_id, task_no, code, name, status, department_id
        ) VALUES (
            1, v_shipment_id, v_stage_id, 'METER-TEST-001', 'METER_TEST', 'Metering Test Task', 'in_progress',
            (SELECT id FROM departments WHERE company_id = 1 LIMIT 1)
        );
    END IF;

    -- Create task for company 999 (no subscription test)
    SELECT id INTO v_shipment_id FROM shipments WHERE company_id = 999 LIMIT 1;

    IF v_shipment_id IS NOT NULL THEN
        INSERT INTO shipment_stages (shipment_id, sequence_no, code, name, status)
        SELECT v_shipment_id, 99, 'TEST_STAGE', 'Test Stage', 'active'
        WHERE NOT EXISTS (
            SELECT 1 FROM shipment_stages WHERE shipment_id = v_shipment_id AND code = 'TEST_STAGE'
        );

        SELECT id INTO v_stage_id FROM shipment_stages
        WHERE shipment_id = v_shipment_id AND code = 'TEST_STAGE';

        -- Use status='created' first (no assignment needed), then complete in test
        DELETE FROM tasks WHERE task_no = 'METER-TEST-999';
        INSERT INTO tasks (
            company_id, shipment_id, stage_id, task_no, code, name, status
        ) VALUES (
            999, v_shipment_id, v_stage_id, 'METER-TEST-999', 'METER_TEST', 'Metering Test Task No Sub', 'created'
        );
    END IF;
END $$;

-- 6a: Completing a task with an active subscription writes exactly one usage_events row
DO $$
DECLARE
    v_task_id BIGINT;
    v_events_before INT;
    v_events_after INT;
    v_points NUMERIC;
BEGIN
    SELECT id INTO v_task_id FROM tasks WHERE task_no = 'METER-TEST-001';
    SELECT COUNT(*) INTO v_events_before FROM usage_events WHERE company_id = 1;

    -- Complete the task
    UPDATE tasks SET status = 'completed', completed_at = now() WHERE id = v_task_id;

    SELECT COUNT(*) INTO v_events_after FROM usage_events WHERE company_id = 1;
    SELECT points_charged INTO v_points FROM usage_events
    WHERE company_id = 1 AND task_id = v_task_id;

    IF v_events_after - v_events_before <> 1 THEN
        RAISE EXCEPTION 'TEST 6a FAILED: Expected 1 new usage_event, got %', v_events_after - v_events_before;
    END IF;

    IF v_points IS NULL OR v_points <= 0 THEN
        RAISE EXCEPTION 'TEST 6a FAILED: Points charged is null or zero';
    END IF;

    RAISE NOTICE 'TEST 6a PASSED: Task completion created 1 usage_event with % points', v_points;
END $$;

-- 6b: Completing a task with no subscription writes zero rows AND task still completes
DO $$
DECLARE
    v_task_id BIGINT;
    v_dept_id BIGINT;
    v_events_before INT;
    v_events_after INT;
    v_task_status task_status;
BEGIN
    SELECT id INTO v_task_id FROM tasks WHERE task_no = 'METER-TEST-999';
    SELECT id INTO v_dept_id FROM departments LIMIT 1;
    SELECT COUNT(*) INTO v_events_before FROM usage_events WHERE company_id = 999;

    -- Assign department (required by tasks_assignment_rule for non-created status)
    -- Then complete the task (company 999 has no subscription)
    UPDATE tasks SET department_id = v_dept_id, status = 'completed', completed_at = now() WHERE id = v_task_id;

    SELECT COUNT(*) INTO v_events_after FROM usage_events WHERE company_id = 999;
    SELECT status INTO v_task_status FROM tasks WHERE id = v_task_id;

    IF v_events_after - v_events_before <> 0 THEN
        RAISE EXCEPTION 'TEST 6b FAILED: Expected 0 new usage_events (no subscription), got %', v_events_after - v_events_before;
    END IF;

    IF v_task_status <> 'completed' THEN
        RAISE EXCEPTION 'TEST 6b FAILED: Task did not complete (status: %)', v_task_status;
    END IF;

    RAISE NOTICE 'TEST 6b PASSED: No subscription = 0 usage_events, task still completed';
END $$;

-- Switch back to authenticated role for RLS tests
SET ROLE authenticated;

-- 6c: A tenant cannot read another tenant's usage_events
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);
    SELECT COUNT(*) INTO v_count FROM usage_events WHERE company_id = 999;

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'TEST 6c FAILED: Company 1 saw % of Company 999 usage_events', v_count;
    END IF;
    RAISE NOTICE 'TEST 6c PASSED: Company 1 cannot see Company 999 usage_events';
END $$;

-- 6d: The authenticated role cannot read tenant_costs at all
DO $$
DECLARE
    v_count INT;
BEGIN
    PERFORM set_config('app.company_id', '1', TRUE);

    BEGIN
        SELECT COUNT(*) INTO v_count FROM tenant_costs;

        IF v_count = 0 THEN
            RAISE NOTICE 'TEST 6d PASSED: tenant_costs returned 0 rows (RLS blocks all)';
        ELSE
            RAISE EXCEPTION 'TEST 6d FAILED: Authenticated role saw % tenant_costs rows', v_count;
        END IF;
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'TEST 6d PASSED: tenant_costs access denied';
    END;
END $$;

-- 6e: Overlapping subscription periods are rejected
RESET ROLE;

DO $$
DECLARE
    v_plan_id BIGINT;
BEGIN
    SELECT id INTO v_plan_id FROM billing_plans WHERE code = 'BUSINESS' LIMIT 1;

    BEGIN
        -- Try to insert overlapping subscription (company 1 already has active subscription)
        INSERT INTO company_subscriptions (
            company_id, plan_id, status,
            started_on, current_period_start, current_period_end
        ) VALUES (
            1, v_plan_id, 'active',
            CURRENT_DATE, CURRENT_DATE + 15, CURRENT_DATE + 45  -- Overlaps existing period
        );

        RAISE EXCEPTION 'TEST 6e FAILED: Overlapping subscription was allowed';
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE NOTICE 'TEST 6e PASSED: Overlapping subscription rejected by EXCLUDE constraint';
    END;
END $$;

SET ROLE authenticated;

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
--
-- USAGE METERING TESTS (after 10_usage_metering.sql):
--   6a: PASS - task completion with subscription creates usage_event
--   6b: PASS - task completion without subscription creates 0 events, task completes
--   6c: PASS - tenant isolation on usage_events
--   6d: PASS - tenant_costs blocked for authenticated role
--   6e: PASS - overlapping subscriptions rejected
--
-- Total: 14 tests passing
-- =============================================================================
