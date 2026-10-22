# Potential ADR: Dynamic Balance Derivation Without Static Balance State

**Module**: AGG
**Category**: Architecture
**Priority**: Must Document (Score: 135)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

⚠️ **SIMILAR DECISION EXISTS IN ARCHITECTURE DOCS**

This decision is explicitly referenced in the High-Level Design document:
- **ADR-001 (HLD-001.md)**: *Saldo Derivado Dinamicamente* — "Não armazenar saldo estático na tabela `users`. Motivação: Elimina condições de corrida e inconsistências contábeis. A performance é garantida por meio do índice composto `(user_id, occurred_at)`."
- **RF-008 (PRD-001.md)**: *Derivação Dinâmica de Saldos* — "O saldo e os resultados do período são calculados exclusivamente a partir da agregação de fatos registrados, sem uso de campos estáticos de saldo na conta do usuário."

**Recommended Actions**:
- Formalize `ADR-001` from `docs/HLD-001.md` into a complete MADR document in `docs/adrs/generated/` during Phase 3 (`/adr-generate`).
- Cross-reference the composite index decision in `[DATA]` (`idx_transactions_user_date`) and the decoupled recurrence execution model in `[REC]` (`ADR-002` / `ADR-004`).

---

## What Was Identified

The system intentionally omits any static, mutable balance column (such as `current_balance` or `cached_balance`) from the `users` table and avoids maintaining materialized balance snapshot tables. Instead, `FinancialAggregationService` dynamically derives both the selected period's net result (`total_income - total_expense`) and the user's cumulative historical balance (`accumulated_balance`) on every read or reactive mutation directly from the authoritative `transactions` ledger up to the filter's `@end_date` boundary.

This pattern was established in the foundational architecture specifications (`docs/HLD-001.md`, `docs/PRD-001.md`, and `docs/tech_spec.md`, dated 2026-10-17). By treating `transactions` as an append/edit-friendly ledger of effective financial facts (`income` and `expense`) and computing balances on the fly via SQL `SUM(CASE WHEN ...)` projections supported by the composite B-tree index `idx_transactions_user_date (user_id, occurred_at DESC)`, the architecture guarantees deterministic mathematical consistency between the transaction statement and displayed balance cards.

## Why This Might Deserve an ADR

- **Impact**: Governs the entire accounting model across `[AGG]` (`FinancialAggregationService`), `[DATA]` (`users` and `transactions` schema and indexing), `[TXN]` (manual transaction CRUD), `[REC]` (background recurring transaction generation), and `[WEB]` (Turbo Stream dashboard metric replacements).
- **Trade-offs**: Trades a small, predictable read-time SQL aggregation cost (`O(N)` index scan per user up to `@end_date`) for total elimination of write-time lock contention on the `users` row, lost-update race conditions during concurrent Sidekiq worker executions, and accounting drift when historical transactions are edited or deleted.
- **Complexity**: Eliminates complex two-phase balance reconciliation, database triggers, or compensating ledger adjustments whenever past transactions are modified or removed.
- **Team Knowledge**: Every engineer working on transactions, recurrences, or dashboard features must know never to introduce cached balance columns on `users` or bypass `FinancialAggregationService` for balance calculations.
- **Future Implications**: As a user's lifetime transaction volume grows over multiple years, historical cumulative queries (`occurred_at <= @end_date`) will scan all prior rows for that tenant; if scale eventually demands snapshots, periodic checkpointing can be layered internally within `FinancialAggregationService` without changing controller contracts.
- **Temporal Context**: Foundational architectural invariant established on 2026-10-17 across `PRD-001.md` (v1.1.0), `HLD-001.md` (v1.1.0), and `tech_spec.md` (v1.0.0).

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Lines 45, 73-75
  - Defines `FinancialAggregationService` responsibility and formally declares `ADR-001: Saldo Derivado Dinamicamente`.
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md) - Lines 26-30, 51, 60
  - Specifies `RF-008: Derivação Dinâmica de Saldos` and the business acceptance criterion requiring zero accounting discrepancy between statement rows and consolidated balances.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 13-21, 41-42, 77-136
  - Shows the `users` DDL without any balance column, the mandatory composite index `idx_transactions_user_date`, and the full Ruby implementation of `FinancialAggregationService`.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 11, 24, 76, 300-335
  - Documents the intentional absence of a static balance attribute on `USER` and illustrates the runtime SQL `SUM` sequence in `DashboardAggregatorService`.

### Code Evidence
```ruby
# From docs/tech_spec.md:102-134 (app/services/financial_aggregation_service.rb)
def call
  # 1. Totais consolidados do período selecionado
  period_aggregates = @user.transactions
    .where(occurred_at: @start_date..@end_date)
    .select(
      "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) AS income",
      "COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) AS expense"
    ).take

  income = period_aggregates.income.to_d
  expense = period_aggregates.expense.to_d
  result = income - expense

  # 2. Saldo acumulado histórico total até o fim do período
  accumulated_balance = @user.transactions
    .where("occurred_at <= ?", @end_date)
    .select(
      "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE -amount END), 0) AS balance"
    ).take.balance.to_d
```

```sql
-- From docs/tech_spec.md:13-21 & 41-42
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_digest VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Índice composto obrigatório para agrupamento por usuário e ordenação/filtro temporal
CREATE INDEX idx_transactions_user_date ON transactions (user_id, occurred_at DESC);
```

### Impact Analysis
- Introduced: 2026-10-17 (Specification baseline in `PRD-001.md`, `HLD-001.md`, `tech_spec.md`)
- Affects: 4 documentation specifications (`HLD-001.md`, `PRD-001.md`, `tech_spec.md`, `sqr-finance-diagrams.md`) and 5 system modules (`AGG`, `DATA`, `TXN`, `REC`, `WEB`)
- Recent themes: "accounting consistency", "race condition elimination", "indexed SQL aggregation"

### Alternatives (if observable)
- **Static `balance` column on `users` updated via ActiveRecord callbacks or SQL triggers**: Explicitly rejected in `HLD-001.md` (ADR-001) and `PRD-001.md` (RF-008) due to race conditions during concurrent background job writes and risk of drift when historical transactions are edited or deleted.
- **In-memory Ruby collection summation (`@user.transactions.sum { ... }` after loading AR objects)**: Rejected in `tech_spec.md` (Section 2.1) to avoid instantiating large ActiveRecord collections in Ruby heap memory.

## Questions to Address in ADR (if created)

- How does dynamic SQL derivation eliminate concurrency anomalies between synchronous user mutations (`POST /transactions`) and asynchronous `RecurrenceWorker` jobs?
- What is the expected cardinality of transactions per user per year, and up to what threshold does `idx_transactions_user_date (user_id, occurred_at DESC)` sustain sub-100ms response times without monthly snapshot checkpoints?
- Why is `accumulated_balance` scoped to `occurred_at <= @end_date` (historical balance at the end of the filtered period) rather than `NOW()`?

## Related Potential ADRs
- [`in-database-sql-pushdown-aggregation-with-bounded-temporal-window.md`](../../consider/AGG/in-database-sql-pushdown-aggregation-with-bounded-temporal-window.md) (AGG)
- Composite Index Optimization and Database-Level Domain Constraints (DATA)
- Server-Driven Reactive UI with Hotwire Turbo Streams (WEB)

## Additional Notes
- `docs/HLD-001.md` and `docs/tech_spec.md` name the service `FinancialAggregationService`, whereas `docs/mermaid/sqr-finance-diagrams.md` refers to `DashboardAggregatorService`. The formal ADR should standardize on `FinancialAggregationService`.
