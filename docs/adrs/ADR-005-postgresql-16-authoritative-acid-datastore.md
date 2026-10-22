# ADR-005: PostgreSQL 16 as Authoritative ACID Datastore with Defense-in-Depth CHECK Constraints and Composite Indexing

- **Status:** Accepted
- **Date:** 2026-10-22
- **Module:** `[DATA]`
- **Category:** Technology / Architecture / Performance
- **Deciders:** Sqr Finances Core Architecture Team
- **Related ADRs:**
  - [ADR-001: Saldo Derivado Dinamicamente (`AGG` / `DATA`)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)
  - [ADR-002: Desacoplamento de Transações Geradas e Preservação de Histórico (`REC` / `TXN`)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)
  - [ADR-004: Idempotência de Background via Banco Relacional (`REC` / `DATA`)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)

---

## 1. Context and Problem Statement

Sqr Finances is a personal financial control and cash flow management system where data integrity, monetary precision, concurrency safety, and low query latencies are non-negotiable.

In typical web application architectures, relational databases are often treated merely as passive persistent object stores, delegating domain validation and data invariants entirely to the application layer (ActiveRecord ORM validations). However, this leaves systems vulnerable to:
1. Floating-point calculation drift (IEEE 754 precision loss when computing monetary sums).
2. Data corruption caused by raw SQL queries, data migrations, console operations, or third-party client writes that bypass application ORMs.
3. Race conditions and duplicate records during background worker concurrency and at-least-once retry delivery.
4. Slow dashboard aggregations when volume scales, leading teams to introduce fragile caching columns (such as static balances).

A foundational persistence strategy was needed to guarantee authoritative ACID consistency, exact monetary values, and sub-100ms analytical calculations.

---

## 2. Decision Drivers

- **ACID Authority**: Ensure transactions cannot be committed in inconsistent states, regardless of the entry point (web controllers, background workers, or administrative console scripts).
- **Exact Monetary Arithmetic**: Completely eliminate floating-point approximation errors in currency values.
- **Defense-in-Depth Invariants**: Enforce core business rules directly at the DDL schema layer via SQL `CHECK` and `UNIQUE` constraints in tandem with ActiveRecord validations.
- **Dynamic Ledger Aggregation**: Deliver sub-100ms responses for multi-tenant temporal queries and dynamic balance derivations without maintaining stale static balance columns.
- **Operational Simplicity**: Use a rock-solid, widely supported, open-source relational database containerized locally via Docker Compose.

---

## 3. Considered Options

1. **PostgreSQL 16 with Defense-in-Depth DDL Constraints (Chosen)**
2. **PostgreSQL with Application-Only Validations (Passive ORM store)**
3. **MySQL 8.0**
4. **SQLite 3 (Production via Litestream/Solid)**

---

## 4. Decision

We chose **PostgreSQL 16** (accessed via Rails 8 ActiveRecord and the `pg` gem) as the authoritative relational ACID datastore for all user identities, financial transactions, recurrence rules, and execution audit logs.

Specifically, the architecture establishes the following database design standards:

### 4.1 Fixed-Point Monetary Precision (`NUMERIC(12, 2)`)
All financial quantities (`transactions.amount`, `recurrences.amount`) are defined as `NUMERIC(12, 2)` at the schema layer and mapped to `BigDecimal` (`to_d`) in Ruby, guaranteeing exact cents representation without floating-point drift up to 9,999,999,999.99 BRL.

### 4.2 Dual-Layer Defense-in-Depth Constraints
Domain rules are enforced symmetrically in ActiveRecord validations and PostgreSQL constraints:
- **Strictly Positive Amounts**:
  - `CONSTRAINT chk_positive_amount CHECK (amount > 0)` on `transactions`.
  - `CONSTRAINT chk_rec_amount CHECK (amount > 0)` on `recurrences`.
- **Allowed Transaction Types**:
  - `CONSTRAINT chk_transaction_type CHECK (transaction_type IN ('income', 'expense'))` on `transactions`.
  - `CONSTRAINT chk_rec_transaction_type CHECK (transaction_type IN ('income', 'expense'))` on `recurrences`.
- **Payment Method Invariants**:
  - `CONSTRAINT chk_payment_method CHECK ((transaction_type = 'income' AND payment_method IS NULL) OR (transaction_type = 'expense' AND payment_method IN ('pix', 'debit', 'boleto', 'cash')))` on `transactions`.
  - Symmetric `CONSTRAINT chk_rec_payment_method` on `recurrences`.
- **Recurrence Frequency & Window Rules**:
  - `CONSTRAINT chk_rec_frequency CHECK (frequency IN ('weekly', 'monthly', 'yearly'))` on `recurrences`.
  - `CONSTRAINT chk_rec_dates CHECK (end_date IS NULL OR end_date >= start_date)` on `recurrences`.
- **Tenant Uniqueness & Concurrency Idempotency**:
  - Unique tenant identity: `UNIQUE(username)` and `UNIQUE(email)` on `users`.
  - Idempotent recurrence execution: `CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)` on `recurrence_executions`.

### 4.3 `VARCHAR` with `CHECK` Constraints Over Native `ENUM`
Domain enumerations (`transaction_type`, `payment_method`, `frequency`) use `VARCHAR(20)` constrained by `CHECK` expressions rather than PostgreSQL native `ENUM` types or separate lookup tables. This provides:
- Simpler schema migrations (adding new payment methods requires a lightweight `ALTER TABLE ... ADD CONSTRAINT` without complex PostgreSQL enum alteration locks).
- Natural serialization with Rails string/symbol attributes.
- Protection against invalid strings at the database boundary without the join overhead of lookup tables.

### 4.4 Tenant-Prefixed Composite B-Tree Indexing
Multi-tenant queries and temporal aggregations are accelerated via composite B-tree indexes:
- `idx_transactions_user_date ON transactions (user_id, occurred_at DESC)`: Empowers `FinancialAggregationService` to compute period income, expense, and cumulative balances in under 100ms via index-only or index-range scans.
- `idx_recurrences_user_active ON recurrences (user_id, active) WHERE deleted_at IS NULL`: Partial index enabling the daily Sidekiq Cron sweeper to identify active rules instantly.

### 4.5 Referential Integrity & Audit History Preservation
- Recurrence soft-deletion is enforced via `deleted_at TIMESTAMP WITH TIME ZONE` and `active = FALSE`.
- `recurrence_executions.recurrence_id` uses `ON DELETE RESTRICT` to prevent accidental loss of audit history.
- `recurrence_executions.transaction_id` is nullable and uses `ON DELETE SET NULL`, ensuring that if a user manually deletes a materialized transaction, the historical execution record (`scheduled_for`) is preserved to prevent duplicate re-generation.

---

## 5. Consequences

### Positive
- **Guaranteed Consistency**: Invalid financial records cannot exist in PostgreSQL under any circumstances, even if an ORM validation is bypassed or misconfigured.
- **Zero Balance Drift**: Dynamic balance computation (`ADR-001`) relies directly on indexed SQL aggregation, eliminating out-of-sync static balance columns.
- **Concurrency Safety**: Workers processing recurrence jobs concurrently or retrying after network errors are safely deduplicated by `uq_recurrence_cycle` (`ADR-004`).
- **High Performance**: Index-optimized queries allow the modular monolith to serve dashboard metrics with sub-100ms latency.

### Negative / Trade-offs
- **Coupled Migrations**: Changing domain values (such as adding a new payment method) requires updating both Ruby code constants/validations and executing a PostgreSQL DDL migration.
- **Write Overhead**: Additional composite indexes and constraint evaluations slightly increase write latency per INSERT/UPDATE, which is an intentional and acceptable trade-off for financial accuracy in an MVP workload.

---

## 6. References
- DDL Schema Specification: [`docs/tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md`](../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md)
- High-Level Architecture: [`docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md`](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
- Codebase Mapping: [`docs/adrs/mapping.md`](mapping.md)
