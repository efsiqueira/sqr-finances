# Potential ADR: Decoupled Materialized Financial Transaction Facts

**Module**: TXN
**Category**: Architecture
**Priority**: Must Document (Score: 135)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

⚠️ **SIMILAR DECISION EXISTS**

This decision appears similar to:
- **ADR-002 (documented in `docs/HLD-001.md`)**: Desacoplamento de Transações Geradas (85% keyword match)
  - Module: TXN / REC, Date: 2026-10-17, Status: Accepted (in HLD-001)
  - Common keywords: transactions, recurrence, decoupled, immutable, history

**Timeline**: Documented in `docs/HLD-001.md` (2026-10-17) during the initial architecture specification phase.

**Recommended Actions**:
- Formalize `HLD-001.md` ADR-002 into a standalone MADR document under `docs/adrs/generated/`
- Reconcile the schema discrepancy between `docs/tech_spec.md` (which decouples `transactions` via `recurrence_executions`) and `docs/mermaid/sqr-finance-diagrams.md` (which depicts a direct `recurrence_id` foreign key on `transactions`)

---

## What Was Identified

In the `TXN` module (`app/models/transaction.rb` and the `transactions` table in `docs/tech_spec.md`), the system models every entry in `transactions` strictly as a **materialized, effective financial fact** representing cash flow that has already occurred (`income` or `expense`). The architecture intentionally excludes pending/scheduled transaction states from the `transactions` ledger (PRD-001 Section 2.2) and omits any direct foreign key reference (`recurrence_id`) from `transactions` to `recurrences`.

When a recurring rule (`Recurrence`) is processed by `RecurrenceExecutionService`, the resulting `Transaction` is inserted into `transactions` as an autonomous, standalone record owned directly by `User` (`user_id`), while execution lineage and cycle idempotency are tracked separately in the `recurrence_executions` join/audit table. Introduced in the October 2026 architecture specification (`docs/HLD-001.md`, `docs/tech_spec.md`, and `docs/PRD-001.md`), this pattern guarantees historical immutability (RF-006): editing, pausing, or deleting a `Recurrence` rule only affects future cycles and never mutates or cascades deletions to previously materialized transactions.

## Why This Might Deserve an ADR

- **Impact**: Defines the core domain boundary between `[TXN]` (effective ledger facts) and `[REC]` (periodic generation rules), simplifying `[AGG]` (`FinancialAggregationService`) so it can aggregate all rows in `transactions` without filtering by status (`pending` vs. `settled`) or joining `recurrences`.
- **Trade-offs**: Because `transactions` has no direct `recurrence_id` column in `tech_spec.md`, identifying whether a transaction originated from a recurrence requires joining through `recurrence_executions`. Additionally, `recurrence_executions` defines `ON DELETE CASCADE` on `recurrence_id`, meaning hard-deleting a `Recurrence` preserves the `Transaction` row (satisfying RF-006) but removes the `recurrence_executions` lineage record.
- **Complexity**: Eliminates complex temporal projection logic and retroactivity bugs when users change a recurring bill's amount or delete a subscription.
- **Team Knowledge**: Every engineer working on `[TXN]`, `[REC]`, `[AGG]`, or `[WEB]` must understand why `transactions` contains only consolidated facts and why `recurrence_id` is absent from `transactions` despite appearing in an earlier ERD diagram.
- **Future Implications**: If future roadmap features introduce forecasted cash flow or pending transactions, they must be modeled outside the effective `transactions` ledger (or via separate projection services) to preserve deterministic aggregation.
- **Temporal Context**: Stable foundational decision established at project inception (2026-10-17).

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#L54-L78) - Lines 54-78
  - Defines `Transaction` as a materialized financial fact and specifies `ADR-002: Desacoplamento de Transações Geradas`.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L23-L71) - Lines 23-71
  - Defines the authoritative PostgreSQL DDL for `transactions` (without `recurrence_id`) and `recurrence_executions` (linking `recurrence_id` and `transaction_id`).
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L154-L169) - Lines 154-169
  - Shows `RecurrenceExecutionService` creating an independent `Transaction` record on `@recurrence.user.transactions` alongside a `RecurrenceExecution` record.
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md#L35-L49) - Lines 35-49
  - Excludes pending/scheduled transaction statuses from MVP scope (Section 2.2) and mandates historical immutability when recurrence rules are modified or deleted (RF-006).
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md#L57-L68) - Lines 57-68
  - Exhibits an architectural documentation discrepancy where `TRANSACTION` still lists `bigint recurrence_id FK` instead of the `recurrence_executions` table.

### Code Evidence
```sql
-- From docs/tech_spec.md:23-39
CREATE TABLE transactions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    transaction_type VARCHAR(10) NOT NULL, -- 'income', 'expense'
    payment_method VARCHAR(20),            -- 'pix', 'debit', 'boleto', 'cash'
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_positive_amount CHECK (amount > 0),
    CONSTRAINT chk_transaction_type CHECK (transaction_type IN ('income', 'expense')),
    CONSTRAINT chk_payment_method CHECK (
        (transaction_type = 'income') OR 
        (transaction_type = 'expense' AND payment_method IN ('pix', 'debit', 'boleto', 'cash'))
    )
);
```

```ruby
# From docs/tech_spec.md:155-169
ActiveRecord::Base.transaction do
  transaction = @recurrence.user.transactions.create!(
    title: @recurrence.title,
    amount: @recurrence.amount,
    transaction_type: @recurrence.transaction_type,
    payment_method: @recurrence.payment_method,
    occurred_at: @target_date.to_time.middle_of_day
  )

  RecurrenceExecution.create!(
    recurrence: @recurrence,
    transaction: transaction,
    scheduled_for: @target_date
  )
end
```

### Impact Analysis
- Introduced: 2026-10-17 (initial specification in `docs/HLD-001.md`, `docs/PRD-001.md`, `docs/tech_spec.md`)
- Affects: 5 modules (`TXN`, `REC`, `AGG`, `DATA`, `WEB`)
- Recent themes: "immutability", "decoupled recurrence materialization", "effective cash flow ledger"

### Alternatives (if observable)
- **Direct Nullable Foreign Key (`transactions.recurrence_id`)**: Observable in `docs/mermaid/sqr-finance-diagrams.md` (Lines 57-75), where `TRANSACTION` holds a nullable `recurrence_id` FK and a composite unique constraint on `(recurrence_id, occurred_at)`. This was rejected in `HLD-001.md` and `tech_spec.md` in favor of a dedicated `recurrence_executions` table so that `Transaction` remains completely decoupled from `Recurrence` lifecycle changes and user edits to `occurred_at` do not break cycle idempotency keys.

## Questions to Address in ADR (if created)

- Why must `transactions` store only effective/materialized facts rather than both scheduled and settled transactions?
- Why was the link between `Recurrence` and `Transaction` externalized to `recurrence_executions` instead of a nullable `recurrence_id` column on `transactions`?
- What happens to historical `transactions` and `recurrence_executions` when a user deletes a `Recurrence` rule (soft deactivation vs. hard `DELETE` with `ON DELETE CASCADE`)?
- How should `docs/mermaid/sqr-finance-diagrams.md` be updated to align with `docs/tech_spec.md`?

## Related Potential ADRs
- Dynamic Balance Derivation (`AGG` module — `HLD-001.md` ADR-001)
- Relational Idempotency via `recurrence_executions` (`REC` / `DATA` modules — `HLD-001.md` ADR-004)
- [Unsigned Fixed-Point Monetary Model with Dual-Layer Invariant Enforcement](../../consider/TXN/unsigned-monetary-model-with-dual-layer-invariants.md)

## Additional Notes
- **Documentation Discrepancy Alert**: `docs/mermaid/sqr-finance-diagrams.md` (ERD and Class Diagram) still shows `recurrence_id` as an attribute on `Transaction`, whereas `docs/HLD-001.md` and `docs/tech_spec.md` use `recurrence_executions`. Formalizing this ADR will establish a single source of truth for the implementation team.
