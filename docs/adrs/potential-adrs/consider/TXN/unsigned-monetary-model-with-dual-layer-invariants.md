# Potential ADR: Unsigned Fixed-Point Monetary Model with Dual-Layer Invariant Enforcement

**Module**: TXN
**Category**: Architecture
**Priority**: Consider (Score: 95)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

ℹ️ **RELATED DECISIONS**

This decision relates to:
- **ADR-001 (documented in `docs/HLD-001.md`)**: Saldo Derivado Dinamicamente (`AGG` / `DATA`, 2026-10-17)
- **ADR-002 (documented in `docs/HLD-001.md`)**: Desacoplamento de Transações Geradas (`TXN` / `REC`, 2026-10-17)

**Timeline Context**:
- Specified concurrently on 2026-10-17 in `docs/tech_spec.md` and `docs/HLD-001.md`.
- Provides the foundational data integrity guarantees required by `ADR-001` (`FinancialAggregationService`) to compute deterministic SQL aggregations.

**When creating formal ADR**: Reference ADR-001 and ADR-002 in the Related ADRs section.

---

## What Was Identified

The `TXN` module represents all transaction amounts as **strictly positive, unsigned fixed-point decimals** (`NUMERIC(12, 2)` in PostgreSQL and `BigDecimal` via `.to_d` in Ruby), paired with an explicit direction discriminator column (`transaction_type IN ('income', 'expense')`) and a conditional `payment_method` attribute (`'pix'`, `'debit'`, `'boleto'`, `'cash'`). Rather than storing expenses as negative numbers or using integer cents/floating-point types, sign semantics are applied exclusively at aggregation time via SQL conditional expressions (`CASE WHEN transaction_type = 'income' THEN amount ELSE -amount END`).

Furthermore, domain invariants for `Transaction` are enforced through a **dual-layer defense-in-depth strategy**: ActiveRecord model validations in `app/models/transaction.rb` for user-facing feedback, backed by strict PostgreSQL `CHECK` constraints (`chk_positive_amount`, `chk_transaction_type`, and `chk_payment_method`) in the database schema (`docs/tech_spec.md`). Notably, `chk_payment_method` enforces a cross-column conditional invariant at the database engine level: `payment_method` is optional when `transaction_type = 'income'`, but strictly restricted to `('pix', 'debit', 'boleto', 'cash')` (and non-null) when `transaction_type = 'expense'`.

## Why This Might Deserve an ADR

- **Impact**: Governs how monetary values are validated, persisted, and aggregated across `[TXN]`, `[AGG]`, `[REC]`, and `[WEB]`. Any query summing `transactions.amount` must branch on `transaction_type` rather than performing a naive `SUM(amount)`.
- **Trade-offs**: Storing unsigned positive amounts simplifies form inputs, UI display, and validation (`amount > 0` for all records), at the cost of requiring `CASE WHEN transaction_type = ...` clauses in every SQL aggregation query in `FinancialAggregationService`. Duplicating validation rules in both ActiveRecord and PostgreSQL `CHECK` constraints increases migration maintenance when adding new payment methods or transaction types.
- **Complexity**: Prevents IEEE 754 floating-point precision loss and guarantees that background jobs (`RecurrenceExecutionService`), bulk imports, or direct SQL operations cannot bypass ActiveRecord validations to insert zero/negative amounts or expenses without a valid payment method.
- **Team Knowledge**: Developers writing queries against `transactions` must know that `amount` is unsigned (`> 0`) and that adding a new `payment_method` requires both a database migration altering `chk_payment_method` and an ActiveRecord model update.
- **Future Implications**: Scaling beyond `9,999,999,999.99` (`NUMERIC(12, 2)`) or introducing multi-currency support will require evolving this monetary representation.
- **Temporal Context**: Defined in the initial technical specification (2026-10-17).

## Evidence Found in Codebase

### Key Files
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L23-L39) - Lines 23-39
  - Defines `amount NUMERIC(12, 2) NOT NULL` and the three PostgreSQL `CHECK` constraints (`chk_positive_amount`, `chk_transaction_type`, `chk_payment_method`) on `transactions`.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L104-L120) - Lines 104-120
  - Shows how `FinancialAggregationService` branches on `transaction_type` in SQL `SUM(CASE WHEN ...)` and converts results to `BigDecimal` (`.to_d`).
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md#L22-L23) - Lines 22-23 & Line 46
  - Specifies RF-003: strictly positive amounts (`amount > 0`) and mandatory payment method (`pix`, `debit`, `boleto`, `cash`) exclusively for expenses.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md#L98-L110) - Lines 98-110
  - Illustrates the `Transaction` domain class with `validate_positive_amount()`, `income_type()`, and `expense_type()`.

### Code Evidence
```sql
-- From docs/tech_spec.md:27-39
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
```

```ruby
# From docs/tech_spec.md:116-120
accumulated_balance = @user.transactions
  .where("occurred_at <= ?", @end_date)
  .select(
    "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE -amount END), 0) AS balance"
  ).take.balance.to_d
```

### Impact Analysis
- Introduced: 2026-10-17 (initial specification in `docs/tech_spec.md` and `docs/PRD-001.md`)
- Affects: 4 modules (`TXN`, `AGG`, `REC`, `DATA`)
- Recent themes: "monetary precision", "check constraints", "positive amount validation"

### Alternatives (if observable)
- **Signed Monetary Amounts (`amount < 0` for expenses, `amount > 0` for income)**: Rejected in favor of `amount > 0` (`chk_positive_amount`) + `transaction_type` to prevent sign-inversion bugs in user forms and recurrence templates (RF-003).
- **Application-Only Validation (ActiveRecord only)**: Rejected in favor of dual-layer enforcement (ActiveRecord + PostgreSQL `CHECK` constraints) as documented in `HLD-001.md` Section 2 ("PostgreSQL 16: Garantia de integridade ACID, constraints `CHECK`").

## Questions to Address in ADR (if created)

- Why was unsigned `NUMERIC(12, 2)` with a `transaction_type` discriminator chosen over signed amounts or integer cents (`BIGINT` minor units)?
- Should `payment_method` be explicitly constrained to `IS NULL` when `transaction_type = 'income'` in `chk_payment_method`, or is ignoring/permitting it intentional?
- Why isn't the `chk_payment_method` constraint also replicated on the `recurrences` table in `docs/tech_spec.md` (Lines 44-59), which currently only defines `chk_rec_amount` and `chk_rec_dates`?

## Related Potential ADRs
- [Decoupled Materialized Financial Transaction Facts](../../must-document/TXN/decoupled-materialized-transaction-facts.md)
- Dynamic Balance Derivation (`AGG` module — `HLD-001.md` ADR-001)

## Additional Notes
- **Schema Consistency Observation**: In `docs/tech_spec.md`, `transactions` enforces `chk_transaction_type` and `chk_payment_method`, whereas `recurrences` (Lines 44-59) only enforces `chk_rec_amount` and `chk_rec_dates`. If a `Recurrence` is created with an invalid `payment_method` for an expense, it would only fail later when `RecurrenceExecutionService` attempts to insert into `transactions`. Documenting this ADR helps align constraint parity between `transactions` and `recurrences`.
