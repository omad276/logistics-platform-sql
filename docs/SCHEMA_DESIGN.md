# Schema Design Rationale

This document explains the design decisions, trade-offs, and patterns used in the Logistics Operations & Task Dispatch Platform schema.

---

## Contents

- [Core design philosophy](#core-design-philosophy)
- [Multi-tenancy](#multi-tenancy)
- [The workflow engine](#the-workflow-engine)
- [The party model](#the-party-model)
- [Enums vs. lookup tables](#enums-vs-lookup-tables)
- [Money handling](#money-handling)
- [Inventory as a ledger](#inventory-as-a-ledger)
- [Document ownership](#document-ownership)
- [Audit and history](#audit-and-history)
- [Indexing strategy](#indexing-strategy)
- [Constraint naming](#constraint-naming)
- [Known limits and future work](#known-limits-and-future-work)

---

## Core design philosophy

Three principles guided every decision:

1. **Business rules belong in the database.** Application code can be bypassed — by a migration, a background job, a bulk import, or the next developer under deadline. A constraint cannot. If a rule is non-negotiable, it lives in the schema.

2. **Derived data should be computed, not stored.** A stored aggregate can drift from its source with no way to tell which is lying. Views and functions derive values from the authoritative source at query time. Stock on hand is a sum of movements. Profitability is revenue minus costs.

3. **Workflows are configuration, not code.** Adding a "Quality Inspection" task to the reefer workflow should not require a deployment. The template tables exist so that operational changes are rows, not releases.

---

## Multi-tenancy

Every tenant-owned table carries `company_id` as its first foreign key. This is deliberate overkill for a single-company deployment, but:

- Retrofitting multi-tenancy is one of the most expensive changes a system can undergo.
- Including it from day one costs nothing.
- The column structure is ready for PostgreSQL Row-Level Security if needed later.

The pattern is consistent: `company_id` appears immediately after the primary key in every DDL statement, and every query against tenant data should filter on it.

---

## The workflow engine

### Why templates exist

Most logistics software hard-codes the operational flow into application logic. Sea freight has seven stages; air has four; domestic road has two. Every new service line becomes a development ticket.

This schema takes a different position: the workflow is data.

```
contract_types         → workflow_templates
                              ↓
                       stage_templates
                              ↓
                       task_templates
                              ↓
                 task_template_dependencies
```

When a contract is approved, `fn_instantiate_workflow()` reads the appropriate template and creates live stages and tasks. The template is a blueprint; the shipment holds its own copy.

### Conditional stages

Stage templates carry skip conditions:

```sql
skip_if_no_warehouse  BOOLEAN
skip_if_domestic      BOOLEAN
```

These are evaluated at instantiation time. A domestic shipment never sees customs stages. A direct-delivery contract skips warehousing. Same template family, different instantiation.

### Dependencies

Dependencies are declared on templates and replayed onto live tasks. They are **finish-to-start only** — a deliberate simplification. The specification contains no start-to-start or lag relationships, so they aren't implemented.

The dispatch view (`v_ready_tasks`) returns whatever is genuinely unblocked. No procedural logic decides this; it falls out of the dependency graph:

```sql
WHERE NOT EXISTS (
    SELECT 1 FROM task_dependencies td
      JOIN tasks p ON p.id = td.depends_on_task_id
     WHERE td.task_id = t.id
       AND p.status NOT IN ('completed','closed')
)
```

### Why copies, not references?

A shipment in flight holds its own instantiated stages and tasks. Editing a template on Monday cannot silently rewrite Friday's shipment. This is the same pattern as an order line storing the price at the time of sale, not a live reference to the product catalog.

---

## The party model

### One table, not three

A common mistake is to create separate `customers`, `suppliers`, and `carriers` tables. The same legal entity can be:

- A buyer on one contract
- A seller on the next
- A consignee on a third

The role belongs on the **transaction**, not on the party. `parties` is a single table; `contracts` carries `seller_party_id` and `buyer_party_id` columns.

### Party types

The `party_type` enum exists for filtering and UI purposes, not for business logic. A company marked `carrier` today can appear as a buyer tomorrow without a schema change.

---

## Enums vs. lookup tables

### When to use an enum

Enums are used for **lifecycle states** — values that application logic depends on:

```sql
CREATE TYPE shipment_status AS ENUM (
    'draft', 'booked', 'in_transit', 'delivered', 'closed', 'cancelled'
);
```

Adding a new shipment status probably requires code changes anyway (UI, notifications, reporting). The migration is appropriate.

### When to use a lookup table

Lookup tables are used for **taxonomies** — values that operations staff should be able to change:

```sql
contract_types      -- new service lines
workflow_templates  -- new operational patterns
storage_bins        -- new warehouse locations
```

Adding a "Temperature-Controlled Air Freight" contract type should not require a database migration.

---

## Money handling

### Never floating point

All monetary columns use `NUMERIC(precision, scale)`, never `FLOAT` or `DOUBLE`. Floating-point arithmetic produces rounding errors that accumulate into real discrepancies in financial reconciliation.

### Dual-currency storage

Every monetary transaction records:

1. The transaction currency and amount
2. The exchange rate applied
3. The base-currency equivalent

```sql
amount              NUMERIC(15,2) NOT NULL,
currency            CHAR(3)       NOT NULL,
exchange_rate_to_base NUMERIC(12,6) NOT NULL,
base_currency_amount  NUMERIC(15,2) NOT NULL
```

This preserves history. When the AED/USD rate changes next month, the historic margin on a closed shipment does not move.

### Profitability is derived

`v_shipment_profitability` computes margin from the cost ledger at query time. It doesn't store totals that could drift from the underlying records.

---

## Inventory as a ledger

### Signed quantities

`inventory_movements` uses signed quantities:

- Positive = goods in (receipt, return)
- Negative = goods out (dispatch, adjustment)

This is the same pattern as double-entry accounting. A ledger is append-only; you never edit a historic movement — you post a correction.

### Stock is always derived

`v_stock_on_hand` sums movements per warehouse and bin. There is no stored balance column that could fall out of sync.

```sql
SELECT warehouse_id, SUM(quantity) AS on_hand
  FROM inventory_movements
 GROUP BY warehouse_id
```

---

## Document ownership

### The exclusive arc pattern

Documents can belong to shipments, contracts, customs declarations, deliveries, invoices, or incidents. The schema uses an **exclusive arc** with nullable foreign keys:

```sql
shipment_id         UUID REFERENCES shipments,
contract_id         UUID REFERENCES contracts,
customs_decl_id     UUID REFERENCES customs_declarations,
delivery_id         UUID REFERENCES deliveries,
invoice_id          UUID REFERENCES invoices,
incident_id         UUID REFERENCES incidents,

CONSTRAINT documents_single_owner CHECK (
    num_nonnulls(shipment_id, contract_id, customs_decl_id,
                 delivery_id, invoice_id, incident_id) = 1
)
```

### Why not polymorphic association?

The alternative is `entity_type` + `entity_id` — a pattern that cannot be enforced by foreign keys. The database cannot guarantee that `entity_id` actually exists in the referenced table.

The exclusive arc preserves real referential integrity. Exactly one owner, enforced by constraint.

---

## Audit and history

### Task status history

The specification requires every task status change to record date, time, user, action, and reason. This is implemented as a trigger, not application code:

```sql
CREATE TRIGGER trg_tasks_status_history
    AFTER UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION fn_log_task_status();
```

The trigger reads the acting user from a session variable:

```sql
SET app.current_user_id = '1';
```

**Why in the database:** Application code can be bypassed. A trigger cannot. If the row changed, the history exists.

### Append-only tables

`task_status_history` and `audit_log` are append-only. They should never be updated. Consider adding an `AFTER UPDATE` trigger that raises an exception to enforce this.

### The general audit log

`audit_log` captures cross-cutting forensic changes with JSONB before/after snapshots. It's intended for security and compliance, not operational reporting.

---

## Indexing strategy

### Partial indexes for operational queries

A dispatch board never asks about closed tasks. Indexes exist for the queries that matter:

```sql
CREATE INDEX idx_tasks_dispatch
    ON tasks(company_id, status, scheduled_start_at)
    WHERE status IN ('created','assigned','scheduled','in_progress','waiting');
```

The table grows without bound; the index does not.

### Reverse dependency lookup

Task dependencies are keyed by `(task_id, depends_on_task_id)`. But when a task completes, we need to ask: "What does this unblock?" That walks the graph the other way:

```sql
CREATE INDEX idx_task_dependencies_reverse
    ON task_dependencies(depends_on_task_id);
```

### Foreign key indexes

PostgreSQL does not automatically index foreign keys. Every FK column that will be used in joins or lookups has an explicit index.

---

## Constraint naming

All 44 constraints are explicitly named:

```sql
CONSTRAINT contracts_approval_trail CHECK (...)
CONSTRAINT shipments_closure_rule CHECK (...)
CONSTRAINT tasks_hold_reason CHECK (...)
```

This produces useful error messages. When a constraint fails, the application sees `tasks_hold_reason`, not `tasks_check_47`.

---

## Known limits and future work

### Dependency cycles

Self-dependency is blocked:

```sql
CONSTRAINT no_self_dependency CHECK (task_id <> depends_on_task_id)
```

A longer cycle (A → B → C → A) is not. PostgreSQL `CHECK` constraints cannot be recursive. This belongs in:

1. A trigger on `task_dependencies` that walks the graph
2. The template editor, preventing cycle creation at design time

### No partitioning

Three tables grow without bound:

- `tracking_events` — one per milestone per shipment
- `audit_log` — one per significant change
- `task_status_history` — one per status transition

Past roughly 50 million rows, these want range partitioning by month:

```sql
CREATE TABLE tracking_events (
    ...
) PARTITION BY RANGE (event_timestamp);
```

This is not implemented because it adds operational complexity (partition maintenance) without demonstrating anything new about the domain model.

### No Row-Level Security policies

`company_id` is present on every tenant table. RLS policies are not written. They would look like:

```sql
ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;

CREATE POLICY shipments_company_isolation ON shipments
    USING (company_id = current_setting('app.company_id')::uuid);
```

This is left for deployment, not the demo.

### No rate cards

Contract charges are fixed amounts, not tariffs with validity windows. A production forwarder would eventually need:

```sql
CREATE TABLE rate_cards (
    id UUID PRIMARY KEY,
    origin_zone_id UUID,
    destination_zone_id UUID,
    cargo_type commodity_type,
    valid_from DATE,
    valid_until DATE,
    rate_per_kg NUMERIC(10,4),
    minimum_charge NUMERIC(15,2)
);
```

This is pure configuration complexity. It doesn't demonstrate any new design pattern, so it's omitted.

### Finish-to-start only

Dependencies are finish-to-start. No start-to-start, finish-to-finish, or lag offsets. Every relationship in the specification is finish-to-start; the rest would be complexity without a customer.

---

## Summary

| Decision | Rationale |
|----------|-----------|
| Multi-tenancy from day one | Cheaper than retrofitting |
| Workflow as data | Operational changes don't require deployments |
| One `parties` table | Roles belong on transactions |
| Enums for lifecycles | Code depends on these values |
| Lookup tables for taxonomies | Operations staff can change these |
| `NUMERIC` for money | No floating-point rounding errors |
| Dual-currency storage | Historic margins don't move |
| Signed inventory ledger | Append-only, never edit history |
| `v_stock_on_hand` derived | No stored balance to drift |
| Exclusive arc for documents | Real referential integrity |
| Trigger-based audit | Cannot be bypassed |
| Partial indexes | Table grows, index stays small |
| Named constraints | Useful error messages |

---

## References

- PostgreSQL `CHECK` constraint documentation
- Joe Celko, *SQL for Smarties* — constraint and trigger patterns
- Martin Fowler, *Patterns of Enterprise Application Architecture* — audit log pattern
- Eric Evans, *Domain-Driven Design* — aggregate and lifecycle patterns
