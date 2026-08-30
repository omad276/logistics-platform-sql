#!/bin/bash
# =============================================================================
# test-chain.sh
# Run the full migration chain against a scratch database
# Usage: ./test-chain.sh [database_name]
# =============================================================================
#
# Order: 01 → 02 → 03 → 04 → 06 → 07 → 08 → 09 → 05
#   - 05 (RLS tests) runs LAST because it verifies row counts after full data load
#   - 05 runs as 'authenticated' role so RLS is actually enforced
#
# CRITICAL: Running as postgres superuser bypasses RLS entirely.
# The test suite creates an 'authenticated' role and runs tests as that role
# to verify policies actually work.
#
# =============================================================================

set -e

DB_NAME="${1:-logistics_test}"
PSQL_OPTS="-v ON_ERROR_STOP=1"

echo "=== Dropping and creating database: $DB_NAME ==="
dropdb --if-exists "$DB_NAME"
createdb "$DB_NAME"

echo ""
echo "=== Creating 'authenticated' role for RLS testing ==="
# Create role if not exists (Supabase has this built-in, we need it locally)
psql $PSQL_OPTS -d "$DB_NAME" -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
END
\$\$;
"

echo ""
echo "=== Running 01_schema.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/01_schema.sql

echo ""
echo "=== Running 02_seed.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/02_seed.sql

echo ""
echo "=== Running 03_demo_customs_hold.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/03_demo_customs_hold.sql

echo ""
echo "=== Running 04_countries_customs.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/04_countries_customs.sql

echo ""
echo "=== Running 06_rls_policies.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/06_rls_policies.sql

echo ""
echo "=== Running 07_margin_analysis.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/07_margin_analysis.sql

echo ""
echo "=== Running 08_realistic_financials.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/08_realistic_financials.sql

echo ""
echo "=== Running 09_compliance_layer.sql ==="
psql $PSQL_OPTS -d "$DB_NAME" -f sql/09_compliance_layer.sql

echo ""
echo "=== Granting permissions to 'authenticated' role ==="
# Grant access to all tables so RLS policies (not missing permissions) control access
psql $PSQL_OPTS -d "$DB_NAME" -c "
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
"

echo ""
echo "=== Running 05_rls_tests.sql as 'authenticated' role ==="
# SET ROLE switches to authenticated, so RLS policies are enforced
# This is the ONLY way to actually test RLS locally
TEST_OUTPUT=$(psql $PSQL_OPTS -d "$DB_NAME" -c "SET ROLE authenticated;" -f sql/05_rls_tests.sql 2>&1)
echo "$TEST_OUTPUT"

# Check for test failures:
# - RAISE EXCEPTION causes psql to exit non-zero with ON_ERROR_STOP
# - Also check output for FAIL markers (FAILED, FAIL-OPEN, FAIL-CLOSED, CRITICAL)
if echo "$TEST_OUTPUT" | grep -qE "(FAILED|FAIL-OPEN|FAIL-CLOSED|CRITICAL)"; then
    echo ""
    echo "=== RLS TESTS FAILED ==="
    exit 1
fi

echo ""
echo "=== ALL TESTS PASSED ==="
echo ""
echo "=== CHAIN COMPLETE ==="
echo ""
echo "Verify with:"
echo "  psql -d $DB_NAME -c \"SET ROLE authenticated; SET app.company_id = '1'; SELECT shipment_no, status FROM shipments;\""
echo "  psql -d $DB_NAME -c \"SELECT * FROM v_shipment_margin_analysis WHERE shipment_id = 1;\""
