# Potential ADR: Thin Controllers with Stateless Domain Service Objects

**Module**: WEB
**Category**: Architecture
**Priority**: Consider (Score: 75)
**Date Identified**: 2026-10-18

---

## What Was Identified

The `[WEB]` layer enforces a **Thin Controllers (`Controllers Magros`)** architectural pattern in which Rails `ActionController` classes (`DashboardController`, `TransactionsController`, `RecurrencesController`) are strictly restricted to HTTP transport concerns: session authentication, tenant boundary resolution via `Current.user`, request parameter sanitization (such as enforcing the maximum 365-day temporal filter bound in `DashboardController`), and selecting the appropriate HTML / Turbo Frame / Turbo Stream view response.

All multi-step domain orchestration, financial consolidation queries, and transactional workflows are delegated to stateless **Domain Service Objects** exposing a uniform `.call(...)` class method interface (`FinancialAggregationService.call(user:, start_date:, end_date:)`, `RecurrenceExecutionService.call(recurrence:, target_date:)`). Furthermore, data returned from aggregation services to controllers is encapsulated in immutable Ruby 3.3 `Data.define` Value Object DTOs (`FinancialAggregationService::Result`), preventing view templates or controllers from mutating domain state or triggering accidental N+1 queries.

## Why This Might Deserve an ADR

- **Impact**: Governs the structural boundary between the `[WEB]` presentation layer and the `[AGG]`, `[REC]`, and `[TXN]` domain modules, ensuring that domain logic can be invoked identically by synchronous HTTP controllers and asynchronous Sidekiq workers (`[ASYNC]`).
- **Trade-offs**: Introduces an additional service and DTO abstraction layer beyond standard Rails "fat model / skinny controller" conventions, trading minor boilerplate for clear separation of concerns, isolated unit testability, and reusable synchronous/asynchronous execution paths.
- **Complexity**: Standardizes service invocation (`.call` class constructor delegation), immutable return contracts (`Data.define`), and controller-level guardrails (e.g., bounding custom date filters to `<= 365 days` before invoking `FinancialAggregationService` to guarantee `< 100ms` SQL execution).
- **Team Knowledge**: Engineers adding endpoints must know where controller responsibility ends (HTTP params, `Current.user` scoping, 365-day range validation, Turbo response rendering) and where service objects and immutable DTOs begin.
- **Future Implications**: Standardizing on `.call` service objects and `Data.define` DTOs allows future API controllers, CLI tasks, or background jobs to reuse domain logic without coupling to `ActionController` request context.
- **Temporal Context**: Defined in the initial architecture specification on 2026-10-17 (`HLD-001.md` v1.1.0 and `tech_spec.md` v1.0.0).

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Lines 21-36, 42-46
  - Depicts `Rails 8 Application Server (Controllers Magros + Current.user)` delegating synchronous calls to `Domain Services` (`FinancialAggregationService`, `RecurrenceProcessorService`).
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 77-136
  - Implements `FinancialAggregationService.call(user:, start_date:, end_date:)` returning the immutable `Result = Data.define(:total_income, :total_expense, :period_result, :accumulated_balance, :transactions)` value object to the controller layer.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 14, 83, 209-242, 297-336
  - Illustrates `TransactionsController` and `DashboardController` validating temporal bounds (max 365 days), delegating to domain services, receiving a consolidated DTO, and rendering Turbo Stream/Frame partials.

### Code Evidence
```ruby
# Specified in docs/tech_spec.md:82-95 — Stateless Service + Immutable DTO Contract for Controllers
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
```

```markdown
<!-- Specified in docs/HLD-001.md:44-45 -->
| **Web Layer (Controllers & Hotwire)** | Síncrono | Autenticação, autorização de escopo (`Current.user`), recebimento de formulários e renderização de Turbo Streams/Frames. |
| **FinancialAggregationService** | Serviço de Domínio | Consolidação em nível de banco de dados (queries SQL otimizadas) de entradas, saídas, resultado e saldo acumulado. |
```

### Impact Analysis
- Introduced: 2026-10-17 (Specification baseline in `docs/HLD-001.md` and `docs/tech_spec.md`)
- Affects: All controllers in `[WEB]` (`DashboardController`, `TransactionsController`, `RecurrencesController`) and service interfaces in `[AGG]`, `[REC]`, and `[TXN]`
- Recent themes: "Thin Controllers", "Domain Services", "Data.define DTO", "365-day filter bound"

### Alternatives (if observable)
- **Fat ActiveRecord Models / Controller Query Chaining**: Placing multi-metric SQL aggregations and recurrence generation directly inside controllers or model callbacks was avoided to keep `Transaction` and `Recurrence` focused on data integrity validations (`docs/mermaid/sqr-finance-diagrams.md`, Line 83) and to share stateless service execution between HTTP requests and Sidekiq workers.

## Questions to Address in ADR (if created)

- Should simple single-model CRUD operations in `TransactionsController` go directly through `@user.transactions.create(transaction_params)` in the controller, or through a dedicated `TransactionService` (as depicted in `docs/mermaid/sqr-finance-diagrams.md` Diagram 4) so that `@metrics` recalculation via `FinancialAggregationService` is encapsulated?
- What is the standard error-handling contract between Domain Services and Controllers (e.g., raising `ActiveRecord::RecordInvalid` vs. returning a result monad/struct)?
- How should `DashboardController` handle requests whose custom date range exceeds the 365-day limit (RF-007) — return `HTTP 422 Unprocessable Entity`, clamp the date range to 365 days, or flash an error via Turbo Stream?

## Related Potential ADRs
- [Server-Driven Reactive UI with Rails 8 and Hotwire](../../must-document/WEB/server-driven-reactive-ui-with-rails-8-and-hotwire.md) (`WEB`)
- Dynamic Balance Derivation via In-Database SQL Aggregation (`AGG` / `DATA`)

## Additional Notes
- Note the naming discrepancy documented in `mapping.md`: `HLD-001.md` and `tech_spec.md` name the aggregation service `FinancialAggregationService`, whereas `sqr-finance-diagrams.md` calls it `DashboardAggregatorService` and also introduces a `TransactionService`. Formalizing this ADR will resolve the service naming and boundary convention before code generation begins.
