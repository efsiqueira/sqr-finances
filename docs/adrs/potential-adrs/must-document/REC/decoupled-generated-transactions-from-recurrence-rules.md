# Potential ADR: Decoupling Generated Transactions from Recurrence Rules

**Module**: REC
**Category**: Architecture
**Priority**: Must Document (Score: 125)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

⚠️ **SIMILAR DECISION EXISTS IN HLD SUMMARY**

This decision is explicitly summarized in the High-Level Design document and product requirements:
- **ADR-002 (HLD-001.md)**: *Desacoplamento de Transações Geradas* — Generated transactions become independent entities in the `transactions` table so that historical accounting facts remain immutable when a recurrence rule is edited or deleted.
- **RF-006 (PRD-001.md)**: *Imutabilidade do Histórico* — Modifying or deleting a recurrence rule affects only future cycles; previously generated transactions remain intact.

**Recommended Actions**:
- Formalize `ADR-002` into a dedicated MADR document under `docs/adrs/generated/`.
- Resolve the schema modeling discrepancy between `docs/tech_spec.md` (which omits `recurrence_id` from `transactions` and uses `recurrence_executions` with `ON DELETE CASCADE`) and `docs/mermaid/sqr-finance-diagrams.md` (which depicts a nullable `recurrence_id` foreign key directly on `TRANSACTION`).

---

## What Was Identified

In the `REC` (`Recurrence Engine & Idempotent Execution`) module, recurring financial rules (`Recurrence`) do not dynamically project virtual transactions at query time, nor do materialized `Transaction` records maintain a live, mutable inheritance link to their originating `Recurrence`. Instead, when a recurrence cycle becomes due, `RecurrenceExecutionService` snapshots the rule's current attributes (`title`, `amount`, `transaction_type`, `payment_method`) and materializes a standalone row in the `transactions` table associated directly with the `User` (`@recurrence.user.transactions.create!`).

At the relational schema level (`docs/tech_spec.md`), the `transactions` table intentionally has no `recurrence_id` foreign key column. Traceability between a `Recurrence` and the `Transaction` it generated is maintained exclusively in a separate technical join/audit table (`recurrence_executions`). Consequently, once a recurring transaction is materialized into the ledger, it becomes an immutable historical financial fact: subsequent updates to the `Recurrence` (e.g., changing the monthly rent amount or payment method) or deletion of the `Recurrence` rule affect only future cycles without retroactively altering past cash flow statements or historical accumulated balances.

## Why This Might Deserve an ADR

- **Impact**: Shapes the core domain boundary between `[REC]` (periodic rule scheduling), `[TXN]` (effective cash flow ledger), and `[AGG]` (`FinancialAggregationService`). Because generated transactions are materialized as standard rows in `transactions`, `FinancialAggregationService` can compute period totals and historical balances using a single uniform SQL `SUM` over `transactions` without joining or evaluating `recurrences`.
- **Trade-offs**: Sacrifices automatic retroactive propagation (if a user configured a recurrence with a typo in `title` or `amount` and wants past occurrences updated, they must edit the materialized transactions individually) in exchange for strict accounting immutability and simpler, faster read aggregations.
- **Complexity**: Introduces a dual-entity write path during cycle materialization (`Transaction` + `RecurrenceExecution`) and requires careful foreign-key cascade design so that deleting a `Recurrence` does not cascade-delete `Transaction` rows.
- **Team Knowledge**: Engineers building recurrence CRUD endpoints (`RecurrencesController`), transaction views, or database migrations must understand why `transactions` does not reference `recurrences` directly and why mutating a `Recurrence` must never trigger cascading updates on past `Transaction` records.
- **Future Implications**: Preserves ledger auditability and deterministic balance derivation (`ADR-001`). However, the team must clarify whether `Recurrence` deletion should be implemented as soft-deactivation (`active = false`) or physical `DELETE`, since `recurrence_executions.recurrence_id` specifies `ON DELETE CASCADE` in `tech_spec.md` (which preserves `transactions` but erases the execution audit log if physically deleted).
- **Temporal Context**: Core architectural invariant established in baseline specifications (`HLD-001.md` v1.1.0, `PRD-001.md` v1.1.0, `tech_spec.md` v1.0.0 — 2026-10-17).

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#L52-L78) - Lines 52-78
  - Defines the conceptual entity relationships (`User`, `Transaction`, `Recurrence`, `RecurrenceExecution`) and specifies `ADR-002: Desacoplamento de Transações Geradas`.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L23-L71) - Lines 23-71
  - Defines PostgreSQL DDL for `transactions` (no `recurrence_id` column), `recurrences`, and `recurrence_executions` (linking `recurrence_id` and `transaction_id`).
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L143-L174) - Lines 143-174
  - Reference implementation of `RecurrenceExecutionService` copying `title`, `amount`, `transaction_type`, and `payment_method` from `@recurrence` into `@recurrence.user.transactions.create!`.
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md#L47-L60) - Lines 47-60
  - Specifies `RF-006: Imutabilidade do Histórico` and business acceptance criterion that deleting a recurrence rule preserves all past transactions originated by it.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md#L26-L76) - Lines 26-76
  - Contains an older/alternative ERD model where `TRANSACTION` has a nullable `recurrence_id FK`, highlighting an architectural evolution/discrepancy that the formal ADR should definitively settle.

### Code Evidence
```ruby
# Example from docs/tech_spec.md:154-169
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

```sql
-- Example from docs/tech_spec.md:23-39, 63-70
-- transactions has no foreign key to recurrences; attributes are copied at execution time
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
    ...
);

CREATE TABLE recurrence_executions (
    id BIGSERIAL PRIMARY KEY,
    recurrence_id BIGINT NOT NULL REFERENCES recurrences(id) ON DELETE CASCADE,
    transaction_id BIGINT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    scheduled_for DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)
);
```

### Impact Analysis
- Introduced: 2026-10-17 (Specification baseline in `HLD-001.md`, `PRD-001.md`, `tech_spec.md`)
- Affects: 4 modules (`REC`, `TXN`, `AGG`, `DATA`)
- Recent themes: Historical immutability, decoupled ledger materialization, audit trail separation

### Alternatives (if observable)
- **Nullable `recurrence_id` Foreign Key directly on `transactions`**: Explicitly observable in [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md#L58-L76), where `TRANSACTION` holds `bigint recurrence_id FK` with a unique constraint on `(recurrence_id, occurred_at)`. This was superseded in `HLD-001.md` and `tech_spec.md` by the `recurrence_executions` table so that `transactions` remains pure and editing a transaction's `occurred_at` date does not break recurrence cycle idempotency.

## Questions to Address in ADR (if created)

- Why are recurring transactions materialized as physical, attribute-copied `Transaction` rows rather than computed virtually or linked via a mutable foreign key?
- Why was the link between `Recurrence` and `Transaction` moved out of `transactions.recurrence_id` (as shown in `sqr-finance-diagrams.md`) into `recurrence_executions` (as specified in `HLD-001.md` and `tech_spec.md`)?
- What happens if a user edits the `occurred_at` date or `amount` of a materialized transaction that was originally generated by a recurrence?
- When a user deletes a `Recurrence` (RF-006), should the system perform a physical `DELETE FROM recurrences` (which cascades to `recurrence_executions` while leaving `transactions` intact) or a soft deletion (`active = false`) to preserve the `recurrence_executions` audit log?

## Related Potential ADRs
- [`database-enforced-idempotency-via-recurrence-execution.md`](./database-enforced-idempotency-via-recurrence-execution.md) (Module `REC` — `ADR-004`)
- Dynamic Balance Derivation (`ADR-001` in Module `AGG`)

## Additional Notes
- Formalizing this ADR provides an ideal opportunity to align `docs/mermaid/sqr-finance-diagrams.md` (ERD Diagram 1 and Class Diagram 2) with the authoritative schema in `docs/HLD-001.md` and `docs/tech_spec.md`.
