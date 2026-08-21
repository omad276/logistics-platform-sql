#!/bin/bash
# =============================================================================
# test-chain.sh
# Run the full migration chain against a scratch database
# Usage: ./test-chain.sh [database_name]
# =============================================================================

set -e

DB_NAME="${1:-logistics_test}"

echo "=== Dropping and creating database: $DB_NAME ==="
dropdb --if-exists "$DB_NAME"
createdb "$DB_NAME"

echo ""
echo "=== Running 01_schema.sql ==="
psql -d "$DB_NAME" -f sql/01_schema.sql

echo ""
echo "=== Running 02_seed.sql ==="
psql -d "$DB_NAME" -f sql/02_seed.sql

echo ""
echo "=== Running 03_demo_customs_hold.sql ==="
psql -d "$DB_NAME" -f sql/03_demo_customs_hold.sql

echo ""
echo "=== Running 04_countries_customs.sql ==="
psql -d "$DB_NAME" -f sql/04_countries_customs.sql

echo ""
echo "=== Running 06_rls_policies.sql ==="
psql -d "$DB_NAME" -f sql/06_rls_policies.sql

echo ""
echo "=== Running 07_margin_analysis.sql ==="
psql -d "$DB_NAME" -f sql/07_margin_analysis.sql

echo ""
echo "=== Running 08_realistic_financials.sql ==="
psql -d "$DB_NAME" -f sql/08_realistic_financials.sql

echo ""
echo "=== CHAIN COMPLETE ==="
echo ""
echo "Verify with:"
echo "  psql -d $DB_NAME -c \"SELECT COUNT(*) AS tables FROM information_schema.tables WHERE table_schema = 'public';\""
echo "  psql -d $DB_NAME -c \"SELECT shipment_no, status FROM shipments;\""
echo "  psql -d $DB_NAME -c \"SELECT * FROM v_shipment_margin_analysis WHERE shipment_id = 1;\""
