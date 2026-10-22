# Potential ADR: In-Database SQL Pushdown Aggregation with Bounded Temporal Window

**Module**: AGG
**Category**: Performance
**Priority**: Consider (Score: 90)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

ℹ️ **RELATED DECISIONS**

This decision directly supports and operationalizes:
- **ADR-001 (HLD-001.md)**: *Saldo Derivado Dinamicamente* — Relies on optimized SQL aggregation queries over `(user_id, occurred_at)` so that dynamic balance derivation meets interactive UI latency targets.
- **ADR-003 (HLD-001.md)**: *Arquitetura Orientada ao Servidor (Hotwire)* — Every transaction creation (`POST /transactions`) and period filter navigation (`GET /dashboard`) re-executes `FinancialAggregationService` synchronously to render updated `dashboard_metrics` Turbo Frames/Streams.

**When creating formal ADR**: Reference `ADR-001` (Dynamic Balance Derivation) and `ADR-003` (Hotwire Server-Driven UI) in the Related ADRs section.

---

## What Was Identified

To support real-time cash-flow consolidation on every dashboard load and Turbo Stream mutation without caching or background pre-aggregation, the `AGG` module encapsulates all metric calculations inside a stateless domain service (`FinancialAggregationService`) that pushes conditional summation down to PostgreSQL (`COALESCE(SUM(CASE WHEN ...)), 0)`), enforces a maximum custom filter window of 365 days (12 months) at the controller boundary, converts SQL `NUMERIC(12, 2)` aggregates into Ruby `BigDecimal` (`to_d`), and packages the output into an immutable Ruby 3.3 value object (`FinancialAggregationService::Result = Data.define(...)`).

Introduced in the 2026-10-17 architecture specifications (`docs/tech_spec.md`, `docs/PRD-001.md`, and `docs/mermaid/sqr-finance-diagrams.md`), this design ensures that period income and period expenses are computed in a single SQL pass without instantiating ActiveRecord `Transaction` models in Ruby memory for aggregation, keeping dashboard query latency below the 100ms target (`sqr-finance-diagrams.md`, line 335).

## Why This Might Deserve an ADR

- **Impact**: Defines the synchronous query execution strategy, memory footprint profile, temporal filter limits (RF-007: max 365 days), and immutable DTO contract (`FinancialAggregationService::Result`) shared between `[AGG]`, `[WEB]`, and `[DATA]`.
- **Trade-offs**: Executes 3 targeted SQL queries per invocation (one single-pass `CASE WHEN` query for period `income` and `expense`, one query for cumulative `accumulated_balance <= @end_date`, and one ordered query for period `transactions`) and restricts custom user date ranges to a maximum of 365 days, trading arbitrary multi-year custom range queries for predictable sub-100ms p95 latency and zero Ruby object allocation overhead during summation.
- **Complexity**: Centralizes timezone boundary normalization (`start_date.beginning_of_day`..`end_date.end_of_day`), null-safe SQL coercion (`COALESCE(..., 0)`), and fixed-point decimal conversion (`to_d`) in one stateless service object.
- **Team Knowledge**: Prevents developers from writing N+1 queries, calling Ruby `.select` / `.sum` on loaded `ActiveRecord::Relation` arrays in views/helpers, or returning mutable hashes to controllers and Turbo partials.
- **Future Implications**: Provides a single choke point (`FinancialAggregationService.call`) if the 3 queries later need to be combined into a single CTE query or augmented with pagination for the `transactions` relation.
- **Temporal Context**: Defined in `tech_spec.md` (v1.0.0) and `PRD-001.md` (v1.1.0) on 2026-10-17.

## Evidence Found in Codebase

### Key Files
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 77-136, 185-196
  - Contains the complete `FinancialAggregationService` implementation using `Data.define`, single-query `SUM(CASE WHEN ...)` period aggregation, `BigDecimal` (`to_d`) conversion, and `dashboard_metrics` Turbo Stream replacement.
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md) - Lines 25-30, 50
  - Specifies `RF-007: Consulta e Filtros Temporais` limiting custom intervals to a maximum of 365 days (12 months).
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 300-335
  - Documents the dashboard aggregation sequence and explicitly notes the 365-day bound to preserve aggregation latency below 100ms.

### Code Evidence
```ruby
# From docs/tech_spec.md:83-135 (app/services/financial_aggregation_service.rb)
class FinancialAggregationService
  Result = Data.define(
    :total_income,
    :total_expense,
    :period_result,
    :accumulated_balance,
    :transactions
  )

  def self.call(user:, start_date:, end_date:)
    new(user, start_date, end_date).call
  end

  def initialize(user, start_date, end_date)
    @user = user
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
  end

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
```

### Impact Analysis
- Introduced: 2026-10-17 (`docs/tech_spec.md`, `docs/PRD-001.md`, `docs/mermaid/sqr-finance-diagrams.md`)
- Affects: 3 modules (`AGG`, `WEB`, `DATA`)
- Recent themes: "SQL pushdown aggregation", "sub-100ms latency", "365-day temporal window", "immutable Data.define DTO"

### Alternatives (if observable)
- **Instantiating ActiveRecord collections in memory**: Explicitly rejected in `tech_spec.md` line 79 (*"Executa cálculos agregados diretamente no PostgreSQL, evitando instanciar coleções inteiras em memória"*).
- **Separate SQL `SUM` queries for period income and period expense**: Shown conceptually in `sqr-finance-diagrams.md` (lines 317-320), whereas `tech_spec.md` (lines 104-109) optimizes both into a single SQL query using conditional `SUM(CASE WHEN ...)` projections.

## Questions to Address in ADR (if created)

- Should this decision be documented as a standalone performance ADR or merged as the implementation strategy section of `ADR-001` (Dynamic Balance Derivation)?
- Should the `transactions` relation returned inside `FinancialAggregationService::Result` be paginated or bounded by a row limit in addition to the 365-day temporal window?

## Related Potential ADRs
- [`dynamic-balance-derivation-without-static-balance-state.md`](../../must-document/AGG/dynamic-balance-derivation-without-static-balance-state.md) (AGG)

## Additional Notes
- Consolidates three closely related implementation choices in `FinancialAggregationService`: (1) single-pass conditional SQL `SUM(CASE WHEN ...)` pushdown, (2) 365-day maximum custom date window enforcement, and (3) Ruby 3.3 `Data.define` immutable value object return contract.
