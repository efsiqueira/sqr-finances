# Codebase Architecture Mapping

## Project Overview
- **Project Name**: Sqr Finance (sqr-finances)
- **Purpose**: Personal financial control and cash flow management web application (MVP) focused on frictionless registration of effective financial transactions (income and expenses), reliable automation of recurring transactions (weekly, monthly, yearly), and instant dynamic consolidation of cash flow metrics across temporal filters.
- **Architectural Pattern**: Modular Web Monolith (Server-Driven UI)
- **Primary Language**: Ruby 3.3+
- **Core Framework**: Ruby on Rails 8.0 with Hotwire (Turbo Drive, Turbo Frames, Turbo Streams, Stimulus JS)
- **Current Repository State**: Specification & Architecture Design Phase (Greenfield — architectural and product documentation consolidated in `docs/`; application source code ready to be generated).

---

## Technology Stack

| Layer / Category | Technology | Version / Specification | Purpose |
|---|---|---|---|
| **Language** | Ruby | 3.3+ | Core programming language; utilizes modern features such as immutable `Data.define` value objects |
| **Web Framework** | Ruby on Rails | 8.0 | Full-stack MVC modular monolith, routing, ActiveRecord ORM, and request lifecycle management |
| **Frontend / Reactive UI** | Hotwire (Turbo & Stimulus) | Rails 8 Default | Server-driven UI updates via Turbo Drive, Turbo Frames (`dashboard_metrics`, `transactions_list`, `transaction_form_container`), and Turbo Streams without a decoupled SPA |
| **Primary Database** | PostgreSQL | 16 | Authoritative ACID relational datastore with `NUMERIC(12,2)` precision, symmetric `CHECK` constraints, composite indexes, and composite `UNIQUE` keys |
| **In-Memory Store / Queue** | Redis | 7 | Backing store and message broker for background job queues |
| **Background Processing** | Sidekiq + Sidekiq Cron | 7 | Asynchronous job processing and daily scheduled cron execution (`00:05 UTC`) for recurring transaction materialization |
| **Authentication** | Rails Auth / `bcrypt` | Standard (`has_secure_password`) | Password hashing (`password_digest`), session-based authentication, and `Current.user` request scoping |

---

## Context Notes

**Source Files**:
- [docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) (Primary Architecture Reference — v1.2.0)
- [docs/prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md) (Product Requirements Document — v1.2.0)
- [docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) (Technical Specification & DDL/Service Design — v1.1.0)
- [docs/mermaid/sqr-finance-diagrams.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/mermaid/sqr-finance-diagrams.md) (Architecture & Domain Diagrams)
- [README.md](file:///home/efsiqueira/meus-projetos/sqr-finances/README.md) (Repository root readme)

**Key Insights**:
- **Architectural Patterns Mentioned**:
  - **Modular Web Monolith**: Centralized Rails 8 deployment combining synchronous HTTP/Hotwire rendering and asynchronous Sidekiq background workers over shared domain services and models.
  - **Server-Driven Reactive UI (Hotwire)**: Eliminates client-side state synchronization and JSON API contract duplication by returning HTML fragments via Turbo Frames and DOM mutations via Turbo Streams.
  - **Thin Controllers & Unified Domain Service Objects**: Controllers manage authentication, tenant scoping (`Current.user`), direct ActiveRecord CRUD on simple entities (`Current.user.transactions`, `Current.user.recurrences`), and response formatting, delegating complex business logic to three stateless service objects (`FinancialAggregationService`, `RecurrenceProcessorService`, and `RecurrenceExecutionService`).
  - **Dynamic State Derivation (Zero Static Balance)**: Account balances and period metrics are never stored as static columns on `users`; they are dynamically calculated via SQL `SUM` aggregations indexed by `(user_id, occurred_at DESC)`.
  - **Database-Enforced Idempotency & Audit History Preservation**: Background job retries and concurrent workers are guarded by an atomic transaction and a relational unique constraint `uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)` on `recurrence_executions`, gracefully rescuing `ActiveRecord::RecordNotUnique`. Recurrence deletions use soft-delete (`deleted_at` + `active = false`), `ON DELETE RESTRICT` on `recurrence_id`, and `ON DELETE SET NULL` on `transaction_id` to preserve complete audit history.
  - **Strict Logical Multi-Tenancy**: Every query is chained through the authenticated user (`Current.user` / `@user.transactions`), returning `HTTP 404 Not Found` on unauthorized cross-tenant resource access to prevent ID enumeration.
- **Business Domains Identified**:
  1. **Identity & Tenant Isolation**: User registration (`username` and `email` uniqueness), authentication, and strict logical multi-tenancy (RF-001, RF-002).
  2. **Effective Cash Flow Transactions**: CRUD operations for concrete financial facts (`income` and `expense`), enforcing strictly positive amounts (`amount > 0`) and required payment methods (`pix`, `debit`, `boleto`, `cash`) exclusively on expenses (RF-003).
  3. **Recurrence Engine & Lifecycle**: Periodic rule definition (`weekly`, `monthly`, `yearly`), lifecycle state management (Active, Paused, Completed, Soft-Deleted via `deleted_at`), and decoupled historical transaction generation with preserved execution history (RF-004, RF-005, RF-006).
  4. **Financial Consolidation & Temporal Analytics**: Real-time SQL aggregation of period income, period expenses, net period result, and historical accumulated balance across day, month, year, or custom date ranges up to 365 days (RF-007, RF-008).
- **Module Boundaries Documented**:
  - `HLD-001-arquitetura-monolito-modular-hotwire.md` and `TS-001-movimentacoes-recorrencias-agregacao.md` explicitly define five structural boundaries:
    1. **Web Layer (Controllers & Hotwire Views)**
    2. **Domain Services (`FinancialAggregationService`, `RecurrenceProcessorService`, `RecurrenceExecutionService`)**
    3. **Asynchronous Workers (`Sidekiq Cron`, `RecurrenceSchedulerWorker`, `RecurrenceWorker`)**
    4. **Domain Models & Persistence (`User`, `Transaction`, `Recurrence`, `RecurrenceExecution` on PostgreSQL 16)**
- **Architectural Alignment Log (2026-10-21)**:
  1. **ERD & Schema Alignment**: `sqr-finance-diagrams.md` was updated to match `HLD-001` and `TS-001`, modeling `recurrence_executions` instead of a direct `recurrence_id` FK on `transactions`.
  2. **History Preservation**: `recurrences` now includes `deleted_at TIMESTAMP WITH TIME ZONE` for soft-deletion; `recurrence_executions.recurrence_id` uses `ON DELETE RESTRICT` and `recurrence_executions.transaction_id` is nullable with `ON DELETE SET NULL`.
  3. **CHECK Constraint Parity**: `recurrences` now enforces `chk_rec_transaction_type`, `chk_rec_frequency`, and `chk_rec_payment_method` (requiring `payment_method IS NULL` on `income` and valid payment method on `expense`), matching `transactions`.
  4. **Service Unification**: Standardized on `FinancialAggregationService`, `RecurrenceProcessorService`, and `RecurrenceExecutionService` across all documents (deprecating `DashboardAggregatorService` and `TransactionService`).

---

## System Modules

### Module Index
1. **[WEB] - Web & Reactive UI Layer**: Synchronous HTTP controllers, authentication/tenant scoping (`Current.user`), and Hotwire (Turbo Frames/Streams & Stimulus) views.
2. **[AUTH] - Identity & Multi-Tenant Access**: User registration, credential authentication (`bcrypt`), session management, and tenant data isolation.
3. **[TXN] - Effective Transactions Management**: Domain model, validations, and persistence for concrete income and expense financial facts.
4. **[AGG] - Financial Consolidation & Dashboard Aggregation**: Database-level SQL aggregation service computing period totals, net results, and cumulative historical balances.
5. **[REC] - Recurrence Engine & Idempotent Execution**: Domain logic for periodic rules, cycle calculation, and atomic, idempotent materialization of recurring transactions.
6. **[ASYNC] - Background Scheduling & Workers**: Sidekiq Cron daily scheduler and asynchronous worker queues backed by Redis 7.
7. **[DATA] - Relational Persistence & Schema Integrity**: PostgreSQL 16 schema, ACID constraints, composite indexes, and idempotency keys.

---

### [WEB]: Web & Reactive UI Layer
- **Purpose**: Handles incoming HTTPS requests, enforces session authentication and tenant scoping via `Current.user`, processes form submissions, validates temporal filter bounds (max 365 days), and renders reactive HTML fragments via Hotwire (Turbo Frames and Turbo Streams).
- **Location**: `app/controllers/*`, `app/views/*`, `app/javascript/controllers/*` (Specified in [HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) and [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Key Components**:
  - `TransactionsController` (`POST /transactions`, CRUD operations via `Current.user.transactions`)
  - `DashboardController` (`GET /dashboard` with period filters: day, month, year, custom range <= 365 days)
  - `RecurrencesController` (CRUD, activation/deactivation, and soft-deletion via `deleted_at` of recurrence rules)
  - Turbo Frame containers: `dashboard_metrics`, `transactions_list`, `transaction_form_container`
  - Turbo Stream templates: `app/views/transactions/create.turbo_stream.erb`
- **Technologies**: Ruby on Rails 8 ActionController, Hotwire (Turbo Drive, Turbo Frames, Turbo Streams), Stimulus JS, ERB templates
- **Dependencies**:
  - *Internal*: `[AUTH]`, `[TXN]`, `[AGG]`, `[REC]`
  - *External*: `turbo-rails`, `stimulus-rails`
- **Patterns**: Server-Driven UI (ADR-003), Thin Controllers, Partial DOM Replacement via Turbo Streams
- **Key Files**:
  - `app/views/transactions/create.turbo_stream.erb` (documented in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Scope**: Medium - Planned module

---

### [AUTH]: Identity & Multi-Tenant Access
- **Purpose**: Manages user account lifecycle, unique identity enforcement (`username` and `email`), password encryption, and strict logical multi-tenant isolation where every query is scoped to the authenticated `User` and unauthorized access returns `HTTP 404 Not Found`.
- **Location**: `app/models/user.rb`, `app/models/current.rb`, `app/controllers/sessions_controller.rb` (Specified in [HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) and [PRD-001-mvp-controle-financeiro-fluxo-caixa.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md))
- **Key Components**:
  - `User` model (`name`, `username`, `email`, `password_digest`, `has_many :transactions`, `has_many :recurrences`)
  - `Current` attributes (`Current.user`)
  - Authentication concern / controller filters
- **Technologies**: Rails 8 Authentication generator / `ActiveModel::SecurePassword` (`bcrypt`), PostgreSQL `UNIQUE` constraints
- **Dependencies**:
  - *Internal*: `[DATA]`
  - *External*: `bcrypt`
- **Patterns**: Logical Multi-Tenancy via Association Chaining (`@user.transactions`), `ActiveSupport::CurrentAttributes`, Security by Indistinguishability (`404 Not Found` on cross-tenant lookup)
- **Key Files**:
  - `app/models/user.rb` (schema defined in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Scope**: Small - Planned module

---

### [TXN]: Effective Transactions Management
- **Purpose**: Represents and validates materialized financial transactions (`income` or `expense`) in the user's cash flow ledger. Enforces strictly positive amounts (`amount > 0`) and validates payment methods (`pix`, `debit`, `boleto`, `cash`) exclusively when `transaction_type == 'expense'` (`NULL` when `income`).
- **Location**: `app/models/transaction.rb` (Specified in [HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) and [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Key Components**:
  - `Transaction` ActiveRecord model
  - Domain validations (`amount > 0`, `transaction_type` inclusion, conditional `payment_method` validation)
  - Temporal scopes (`occurred_at` filtering and descending chronological ordering)
- **Technologies**: ActiveRecord (Rails 8), PostgreSQL `NUMERIC(12, 2)` and `CHECK` constraints
- **Dependencies**:
  - *Internal*: `[AUTH]`, `[DATA]`
  - *External*: `activerecord`
- **Patterns**: Immutable Historical Financial Fact (ADR-002), Dual-Layer Validation (ActiveRecord model + PostgreSQL `CHECK` constraints)
- **Key Files**:
  - `app/models/transaction.rb` (DDL in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Scope**: Small - Planned module

---

### [AGG]: Financial Consolidation & Dashboard Aggregation
- **Purpose**: Consolidates financial metrics directly inside PostgreSQL without loading ActiveRecord collections into Ruby memory. Computes total period income, total period expense, net period result (`income - expense`), historical accumulated balance up to `@end_date`, and fetches the ordered period transactions.
- **Location**: `app/services/financial_aggregation_service.rb` (Specified in [HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) and [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Key Components**:
  - `FinancialAggregationService`
  - `FinancialAggregationService::Result` (immutable value object defined via `Data.define(:total_income, :total_expense, :period_result, :accumulated_balance, :transactions)`)
- **Technologies**: Ruby 3.3 `Data.define`, ActiveRecord SQL `SUM(CASE WHEN ...)` projections, `BigDecimal` (`to_d`)
- **Dependencies**:
  - *Internal*: `[AUTH]`, `[TXN]`, `[DATA]`
  - *External*: PostgreSQL composite index `idx_transactions_user_date`
- **Patterns**: Service Object Pattern, Dynamic Balance Derivation (ADR-001), In-Database SQL Pushdown Aggregation, Value Object DTO (`Data.define`)
- **Key Files**:
  - `app/services/financial_aggregation_service.rb` (reference implementation in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Scope**: Small - Planned module

---

### [REC]: Recurrence Engine & Idempotent Execution
- **Purpose**: Manages periodic transaction rules (`weekly`, `monthly`, `yearly`), evaluates due cycles between `start_date` and optional `end_date`, and executes atomic creation of independent `Transaction` records paired with a `RecurrenceExecution` audit record to guarantee strict idempotency and full historical preservation.
- **Location**: `app/models/recurrence.rb`, `app/models/recurrence_execution.rb`, `app/services/recurrence_processor_service.rb`, `app/services/recurrence_execution_service.rb` (Specified in [HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) and [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Key Components**:
  - `Recurrence` model (`frequency`, `start_date`, `end_date`, `active`, `deleted_at`, payment attributes)
  - `RecurrenceExecution` model (`recurrence_id`, `transaction_id`, `scheduled_for`)
  - `RecurrenceProcessorService` (identifies active, non-deleted recurrences and due cycle dates, enqueuing worker jobs and deactivating expired rules)
  - `RecurrenceExecutionService` (wraps `Transaction.create!` and `RecurrenceExecution.create!` in `ActiveRecord::Base.transaction` and rescues `ActiveRecord::RecordNotUnique`)
- **Technologies**: ActiveRecord Transactions, PostgreSQL `UNIQUE (recurrence_id, scheduled_for)` constraint
- **Dependencies**:
  - *Internal*: `[AUTH]`, `[TXN]`, `[DATA]`
  - *External*: `activerecord`
- **Patterns**: Decoupled Generated Entities & Soft-Delete History Preservation (ADR-002), Relational Idempotency Key / Audit Log (ADR-004), Optimistic Concurrency Handling via Unique Constraint Exception Rescue
- **Key Files**:
  - `app/services/recurrence_processor_service.rb` (reference implementation in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
  - `app/services/recurrence_execution_service.rb` (reference implementation in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Scope**: Medium - Planned module

---

### [ASYNC]: Background Scheduling & Workers
- **Purpose**: Orchestrates unattended daily sweeps of active recurrence rules and dispatches individual cycle execution jobs to background worker queues with automatic retry tolerance.
- **Location**: `app/workers/recurrence_scheduler_worker.rb`, `app/workers/recurrence_worker.rb` (Specified in [HLD-001-arquitetura-monolito-modular-hotwire.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) and [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Key Components**:
  - `RecurrenceSchedulerWorker`: Triggered daily at `00:05 UTC` by Sidekiq Cron; delegates to `RecurrenceProcessorService.call` to enqueue `RecurrenceWorker` jobs for each unprocessed eligible cycle up to the current date.
  - `RecurrenceWorker`: Consumes `(recurrence_id, target_date)` from Redis and invokes `RecurrenceExecutionService.call`.
- **Technologies**: Sidekiq 7, Sidekiq Cron, Redis 7
- **Dependencies**:
  - *Internal*: `[REC]`, `[DATA]`
  - *External*: `sidekiq`, `sidekiq-cron`, `redis`
- **Patterns**: Fan-Out Scheduler / Worker Pattern, At-Least-Once Delivery with Idempotent Consumer (ADR-004)
- **Key Files**:
  - `app/workers/recurrence_scheduler_worker.rb`
  - `app/workers/recurrence_worker.rb`
- **Scope**: Small - Planned module

---

### [DATA]: Relational Persistence & Schema Integrity
- **Purpose**: Acts as the single authoritative source of truth enforcing ACID transactions, monetary precision, symmetric domain check constraints, composite indexing for low-latency temporal queries, and unique constraints for concurrency control.
- **Location**: `db/schema.rb`, `db/migrate/*` (DDL specified in [TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md))
- **Key Components**:
  - `users` table (`UNIQUE` on `username`, `email`)
  - `transactions` table (`NUMERIC(12, 2)`, `chk_positive_amount`, `chk_transaction_type`, `chk_payment_method`, composite index `idx_transactions_user_date ON (user_id, occurred_at DESC)`)
  - `recurrences` table (`deleted_at`, `chk_rec_amount`, `chk_rec_transaction_type`, `chk_rec_frequency`, `chk_rec_payment_method`, `chk_rec_dates`, partial composite index `idx_recurrences_user_active ON (user_id, active) WHERE deleted_at IS NULL`)
  - `recurrence_executions` table (`ON DELETE RESTRICT` on `recurrence_id`, `ON DELETE SET NULL` on nullable `transaction_id`, `uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)`)
- **Technologies**: PostgreSQL 16
- **Dependencies**:
  - *Internal*: None (foundational layer)
  - *External*: `pg` gem, PostgreSQL 16 server
- **Patterns**: Database-Level Domain Invariants (`CHECK` constraints), Composite Index Optimization for Time-Series Partitioning by Tenant, Audit History Preservation
- **Key Files**:
  - [docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md](file:///home/efsiqueira/meus-projetos/sqr-finances/docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md)
- **Scope**: Small - Planned module

---

## Cross-Cutting Concerns

### 1. Multi-Tenant Security & Data Isolation
- **Mechanism**: Logical multi-tenancy anchored on the `User` entity (`user_id` foreign keys on `transactions` and `recurrences`).
- **Enforcement**: Controllers scope all operations through `Current.user` associations (`@user.transactions`, `@user.recurrences`). Any attempt to access or mutate another tenant's records results in `ActiveRecord::RecordNotFound`, rendered as a standard `HTTP 404 Not Found` (RF-002) so attackers cannot infer resource existence.

### 2. Data Layer Integrity & Monetary Precision
- **Precision**: All monetary values (`amount`) use fixed-point `NUMERIC(12, 2)` in PostgreSQL and `BigDecimal` (`to_d`) in Ruby to prevent floating-point rounding errors.
- **Defense-in-Depth Constraints**: Business invariants are enforced symmetrically in ActiveRecord validations and PostgreSQL `CHECK` constraints (`chk_positive_amount`, `chk_transaction_type`, `chk_payment_method`, `chk_rec_amount`, `chk_rec_transaction_type`, `chk_rec_frequency`, `chk_rec_payment_method`, `chk_rec_dates`).
- **Dynamic Balance Consistency**: By omitting any static balance column on `users` (ADR-001) and relying on indexed SQL aggregations (`idx_transactions_user_date`), the system eliminates race conditions and accounting drift between ledger entries and displayed balances.

### 3. Asynchronous Reliability, Idempotency & Audit History Preservation
- **Concurrency Safety**: Sidekiq provides at-least-once job execution, meaning network failures or worker restarts can trigger duplicate job runs for the same recurrence cycle.
- **Database Lockout**: `RecurrenceExecutionService` wraps transaction generation and `RecurrenceExecution` insertion inside a single PostgreSQL ACID transaction guarded by `CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)` (ADR-004). Duplicate executions raise `ActiveRecord::RecordNotUnique`, which is caught and logged as a no-op.
- **Audit Preservation**: Deleting a `Recurrence` performs a soft-delete (`deleted_at = Time.current, active = false`) with `ON DELETE RESTRICT` on `recurrence_executions.recurrence_id`, while `recurrence_executions.transaction_id` uses `ON DELETE SET NULL` so manual transaction deletions never erase cycle execution history.

### 4. Reactive Server-Driven UI (Hotwire)
- **Partial Updates**: Mutations (`POST /transactions`) return `text/vnd.turbo-stream.html` responses that simultaneously prepend the new transaction row (`transactions_table_body`), replace consolidated dashboard metrics (`dashboard_metrics`), and reset the form container (`transaction_form_container`) in a single HTTP round-trip without custom client-side state management.
- **Query Bounding**: Temporal filters in `DashboardController` enforce a maximum custom date window of 365 days (12 months) to guarantee sub-100ms SQL aggregation latency.
