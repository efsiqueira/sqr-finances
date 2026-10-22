# Potential ADR: PostgreSQL 16 as Authoritative ACID Datastore with Defense-in-Depth CHECK Constraints and Composite Indexing

**Module**: DATA
**Category**: Technology / Architecture / Performance
**Priority**: Must Document (Score: 150)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

ℹ️ **RELATED DECISIONS**

This decision relates to foundational architectural decisions documented in `docs/HLD-001.md`:
- **ADR-001**: Saldo Derivado Dinamicamente (`AGG` / `DATA`, 2026-10-17) — Relies directly on PostgreSQL composite index `idx_transactions_user_date ON transactions (user_id, occurred_at DESC)` and `NUMERIC(12, 2)` aggregation precision to compute balances on the fly without static balance columns.
- **ADR-002**: Desacoplamento de Transações Geradas (`REC` / `TXN`, 2026-10-17) — Relies on relational foreign key semantics and independent row persistence in `transactions`.
- **ADR-004**: Idempotência de Background via Banco Relacional (`REC` / `DATA`, 2026-10-17) — Relies on PostgreSQL ACID transactions and the composite unique constraint `uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)` on `recurrence_executions`.

**Timeline Context**:
- Established alongside ADR-001 through ADR-004 in the initial architecture specification (`2026-10-17`, initial repository commit `aa2a47a`).
- Serves as the foundational persistence infrastructure enabling ADR-001, ADR-002, and ADR-004.

**When creating formal ADR**: Reference ADR-001, ADR-002, and ADR-004 in the Related ADRs section.

---

## What Was Identified

Sqr Finance selects **PostgreSQL 16** (accessed via Rails 8 ActiveRecord) as the single, authoritative ACID relational datastore for all user identities, financial transactions, recurrence rules, and execution audit logs. Rather than treating the database as a passive storage bucket controlled solely by application-level ORM validations, the architecture enforces a strict **defense-in-depth schema design** directly inside PostgreSQL DDL.

Specifically, the schema combines three structural mechanisms at the database layer:
1. **Exact Monetary Precision**: All financial columns (`transactions.amount` and `recurrences.amount`) use fixed-point `NUMERIC(12, 2)` paired with Ruby `BigDecimal` (`to_d`), eliminating IEEE 754 floating-point representation drift.
2. **Database-Level Domain Invariants (`CHECK` & `UNIQUE` Constraints)**: Core business rules—such as strictly positive monetary amounts (`chk_positive_amount`, `chk_rec_amount`), allowed transaction types (`chk_transaction_type`), conditional payment method requirements for expenses (`chk_payment_method`), valid recurrence date windows (`chk_rec_dates`), tenant identity uniqueness (`username`, `email`), and cycle execution uniqueness (`uq_recurrence_cycle`)—are enforced directly by PostgreSQL constraints in addition to ActiveRecord model validations.
3. **Workload-Tailored Composite B-Tree Indexing**: Multi-tenant temporal queries and background recurrence sweeps are accelerated via composite indexes prefixed by tenant ID (`idx_transactions_user_date ON transactions (user_id, occurred_at DESC)` and `idx_recurrences_user_active ON recurrences (user_id, active)`).

Introduced in October 2026 (`commit aa2a47a`, specification v1.0.0 / v1.1.0 dated `2026-10-17`) with architectural documentation emphasizing "integridade ACID", "constraints CHECK", "chaves únicas compostas para prevenção de concorrência", and "queries SQL otimizadas", this pattern establishes the foundational data integrity and performance contract prior to application code generation.

## Why This Might Deserve an ADR

- **Impact**: Governs data integrity, concurrency safety, monetary accuracy, and query latency across every backend module (`AUTH`, `TXN`, `AGG`, `REC`, `ASYNC`). Any bypass of ActiveRecord (such as bulk SQL operations, background worker race conditions, or future database clients) remains strictly bounded by PostgreSQL's schema rules.
- **Trade-offs**: Enforcing domain rules via SQL `CHECK` constraints (`chk_payment_method`, `chk_transaction_type`, `chk_positive_amount`) couples schema migrations to domain rule changes (e.g., adding a new payment method or transaction type requires an `ALTER TABLE` DDL migration in addition to updating Ruby constants) and increases write overhead slightly due to index maintenance and constraint evaluation.
- **Complexity**: Coordinates conditional boolean logic inside SQL `CHECK` expressions (`(transaction_type = 'income') OR (transaction_type = 'expense' AND payment_method IN ('pix', 'debit', 'boleto', 'cash'))`), cascading foreign key lifecycles (`ON DELETE CASCADE`), and multi-column index ordering (`user_id, occurred_at DESC`).
- **Team Knowledge**: Engineers must know that schema constraints are mandatory for new financial invariants, that `FLOAT`/`REAL` types are prohibited for currency, and that all analytical/listing queries must align with `(user_id, occurred_at DESC)` to avoid sequential table scans.
- **Future Implications**: Provides a rock-solid accounting foundation capable of scaling to millions of ledger rows per tenant via index-only/index-range scans, while highlighting a known DDL subtlety around `ON DELETE CASCADE` on `recurrence_executions` vs. soft-deactivation (`active = false`) to preserve historical audit trails.
- **Temporal Context**: Foundational specification baseline introduced in `2026-10-17` (1 initial commit, stable architectural specification across `HLD-001.md`, `tech_spec.md`, and `PRD-001.md`).

## Evidence Found in Codebase

### Key Files
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 10-71
  - Defines the complete PostgreSQL 16 DDL schema (`users`, `transactions`, `recurrences`, `recurrence_executions`), `NUMERIC(12, 2)` columns, `CHECK` constraints, `UNIQUE` constraints, and composite indexes.
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Lines 12, 34-36, 48, 73-84
  - Specifies PostgreSQL 16 as the authoritative ACID datastore and links composite indexing and unique constraints to ADR-001 and ADR-004.
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md) - Lines 44-60
  - Establishes functional requirements RF-001 through RF-008 and business acceptance criteria demanding zero duplicate recurrence executions, strictly positive amounts, and deterministic balance calculations.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 17, 21-77, 332-335
  - Documents the Entity-Relationship model, ACID guarantees, composite index usage on `(user_id, occurred_at)`, and the sub-100ms aggregation latency target.

### Code Evidence
```sql
-- Example from docs/tech_spec.md:23-70
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

-- Índice composto obrigatório para agrupamento por usuário e ordenação/filtro temporal
CREATE INDEX idx_transactions_user_date ON transactions (user_id, occurred_at DESC);

CREATE TABLE recurrences (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    transaction_type VARCHAR(10) NOT NULL, -- 'income', 'expense'
    payment_method VARCHAR(20),
    frequency VARCHAR(15) NOT NULL,        -- 'weekly', 'monthly', 'yearly'
    start_date DATE NOT NULL,
    end_date DATE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_rec_amount CHECK (amount > 0),
    CONSTRAINT chk_rec_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX idx_recurrences_user_active ON recurrences (user_id, active);

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
- Introduced: 2026-10-17 (Git commit `aa2a47a`, initial specification baseline)
- Modified: 1 commit in repository history (specification phase)
- Last change: 2026-10-17 ("first commit")
- Affects: All 4 core database tables (`users`, `transactions`, `recurrences`, `recurrence_executions`) and all 7 system modules (`DATA`, `AUTH`, `TXN`, `AGG`, `REC`, `ASYNC`, `WEB`)
- Recent themes: "ACID integrity", "CHECK constraints", "composite indexing", "idempotency keys"

### Alternatives (if observable)
- **Application-Only Validation (ActiveRecord validations without SQL `CHECK` constraints)**: Implicitly rejected in `HLD-001.md` and `tech_spec.md` in favor of dual-layer enforcement so database invariants cannot be violated by raw SQL, console operations, or concurrent background workers.
- **Static Cached Balance Columns on `users` vs. Indexed Dynamic Aggregation**: Explicitly rejected in `HLD-001.md` (ADR-001) and `PRD-001.md` (RF-008) in favor of computing sums dynamically over `NUMERIC(12, 2)` using `idx_transactions_user_date`.
- **Nullable `recurrence_id` Foreign Key directly on `transactions` vs. Dedicated `recurrence_executions` Table**: `docs/mermaid/sqr-finance-diagrams.md` (ERD Diagram 1) illustrates an alternative where `TRANSACTION` holds a nullable `recurrence_id` FK with a unique constraint on `(recurrence_id, occurred_at)`, whereas the authoritative `HLD-001.md` and `tech_spec.md` isolate execution tracking into the `recurrence_executions` table with `UNIQUE (recurrence_id, scheduled_for)`.

## Questions to Address in ADR (if created)

- Why was PostgreSQL 16 chosen as the primary relational database over alternatives (e.g., MySQL, SQLite in production)?
- Why enforce domain enumerations (`transaction_type`, `payment_method`, `frequency`) via `VARCHAR` + `CHECK` constraints instead of native PostgreSQL `ENUM` types or lookup tables?
- Why is `recurrences.frequency` not yet constrained by a `chk_rec_frequency` `CHECK` constraint or conditional `chk_rec_payment_method` constraint in `tech_spec.md` while `transactions` has both?
- How should rule deletion (`RF-006`) be handled in light of `ON DELETE CASCADE` on `recurrence_executions.recurrence_id` so historical execution audit logs are not inadvertently lost if a `recurrences` row is hard-deleted?

## Related Potential ADRs
- **[AGG]** Dynamic Balance Derivation and In-Database SQL Pushdown Aggregation (ADR-001)
- **[REC]** Decoupled Recurrence Transaction Materialization and Relational Idempotency via `recurrence_executions` (ADR-002, ADR-004)
- **[TXN]** Dual-Layer Validation for Effective Cash Flow Transactions

## Additional Notes
- **Schema Consistency Observation**: In `docs/tech_spec.md` (lines 44-59), the `recurrences` table enforces `chk_rec_amount` and `chk_rec_dates`, but omits `CHECK` constraints on `transaction_type IN ('income', 'expense')`, `frequency IN ('weekly', 'monthly', 'yearly')`, and conditional `payment_method` (which are present on `transactions`). Formalizing this ADR provides an ideal opportunity to align `recurrences` `CHECK` constraints with `transactions`.
- **Cascade Deletion Nuance**: In `docs/tech_spec.md` (lines 65-66), `recurrence_executions` specifies `ON DELETE CASCADE` for both `recurrence_id` and `transaction_id`. While deleting a `recurrence` preserves the materialized rows in `transactions` (satisfying `PRD-001.md` RF-006), hard-deleting a `recurrence` row removes its `recurrence_executions` audit trail. The formal ADR should clarify whether `Recurrence` deletion is implemented as a soft state transition (`active = false` / `deleted_at`) or if `recurrence_id` on `recurrence_executions` should use `ON DELETE SET NULL` / `RESTRICT`.
