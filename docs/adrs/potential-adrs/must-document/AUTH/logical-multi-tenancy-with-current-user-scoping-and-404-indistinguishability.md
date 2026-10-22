# Potential ADR: Logical Multi-Tenancy via Current.user Association Scoping and HTTP 404 Indistinguishability

**Module**: AUTH
**Category**: Security
**Priority**: Must Document (Score: 145)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

ℹ️ **RELATED DECISIONS**

This decision relates to:
- **ADR-001**: Saldo Derivado Dinamicamente (`HLD-001.md`, 2026-10-17)
- **ADR-003**: Arquitetura Orientada ao Servidor (Hotwire) (`HLD-001.md`, 2026-10-17)

**Timeline Context**:
- Defined alongside ADR-001 and ADR-003 in the foundational v1.1.0 architecture specifications (`2026-10-17`).
- Directly supports ADR-001 by ensuring that all dynamic SQL balance aggregations (`SUM`) are strictly partitioned by `user_id` via composite index `idx_transactions_user_date ON transactions (user_id, occurred_at DESC)`.

**When creating formal ADR**: Reference ADR-001 and ADR-003 in the Related ADRs section.

---

## What Was Identified

Sqr Finance implements **shared-database, shared-schema logical multi-tenancy** anchored on the `User` root entity (`users.id`), enforced at the application layer through `ActiveSupport::CurrentAttributes` (`Current.user`) and strict ActiveRecord association chaining (`@user.transactions`, `@user.recurrences`). Rather than using separate database schemas per tenant or PostgreSQL Row-Level Security (RLS) policies, every domain entity with financial sensitivity (`transactions` and `recurrences`) holds a mandatory `NOT NULL` foreign key (`user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE`) paired with tenant-leading composite indexes (`idx_transactions_user_date` and `idx_recurrences_user_active`).

To prevent cross-tenant data leakage and resource enumeration (Insecure Direct Object Reference / IDOR), the architecture enforces a **Security by Indistinguishability** policy (RF-002). Controllers and domain services never query `Transaction` or `Recurrence` records by primary key globally; all lookups and aggregations traverse the authenticated user's association graph (`@user.transactions.find(...)` or `@user.transactions.where(...)`). Consequently, any attempt by an authenticated user to read, mutate, or delete a resource belonging to another tenant raises `ActiveRecord::RecordNotFound`, which Rails renders as a standard `HTTP 404 Not Found` rather than `HTTP 403 Forbidden`, preventing attackers from inferring whether a record ID exists in the database.

This pattern was established on 2026-10-17 across `docs/PRD-001.md` (v1.1.0), `docs/HLD-001.md` (v1.1.0), and `docs/tech_spec.md` (v1.0.0) as a foundational security and data-isolation pillar for the greenfield MVP.

## Why This Might Deserve an ADR

- **Impact**: Permeates every synchronous controller in `WEB`, every domain service in `AGG` (`FinancialAggregationService`) and `REC` (`RecurrenceExecutionService`), and the relational schema/indexing strategy in `DATA`.
- **Trade-offs**: Shared-table logical multi-tenancy via association chaining is lightweight, fast, and idiomatic in Rails, but places the burden of discipline on developers—an unscoped query (`Transaction.find(params[:id])`) could bypass tenant isolation unless caught by code review or static analysis, whereas PostgreSQL RLS enforces isolation at the database engine level at the cost of connection pooling and session-variable complexity.
- **Complexity**: Combines relational cascade rules (`ON DELETE CASCADE`), tenant-prefixed composite B-Tree indexing, thread/fiber-local request context (`Current.user`), and deliberate HTTP status masking (`404 Not Found` over `403 Forbidden`).
- **Team Knowledge**: Every engineer writing a controller action, service object, or background worker must know that unscoped queries are forbidden and that `404 Not Found` is an intentional security requirement (RF-002), not a routing bug.
- **Future Implications**: Dictates how future features (e.g., shared family accounts, audit logs, or administrative support views) can be introduced, as `user_id` is tightly coupled as the sole tenant partition key.
- **Temporal Context**: Foundational architecture specification established in October 2026 (`2026-10-17`), designed as a permanent security invariant for the system lifecycle.

## Evidence Found in Codebase

### Key Files
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md) - Lines 21, 45
  - Defines logical multi-tenancy in scope and mandates `HTTP 404 Not Found` for unauthorized cross-tenant access to prevent existence deduction (RF-002).
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Lines 23, 44, 54
  - Establishes `Current.user` scope authorization in Thin Controllers and defines `User` as the security anchor (*tenant* lógico).
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 25, 42, 46, 61, 104-126, 156
  - Defines `user_id` foreign keys with `ON DELETE CASCADE`, tenant-leading composite indexes, and `@user.transactions` / `@recurrence.user.transactions` association scoping in domain services.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 11, 83, 241
  - Documents that multi-tenant isolation is strictly guaranteed by chaining all queries from the logged-in user association.

### Code Evidence
```sql
-- From docs/tech_spec.md:23-25, 42, 44-46, 61
CREATE TABLE transactions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ...
);

-- Índice composto obrigatório para agrupamento por usuário e ordenação/filtro temporal
CREATE INDEX idx_transactions_user_date ON transactions (user_id, occurred_at DESC);

CREATE TABLE recurrences (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ...
);

CREATE INDEX idx_recurrences_user_active ON recurrences (user_id, active);
```

```ruby
# From docs/tech_spec.md:104-126 (FinancialAggregationService)
period_aggregates = @user.transactions
  .where(occurred_at: @start_date..@end_date)
  .select(
    "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) AS income",
    "COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) AS expense"
  ).take

# From docs/tech_spec.md:155-162 (RecurrenceExecutionService)
ActiveRecord::Base.transaction do
  transaction = @recurrence.user.transactions.create!(
    title: @recurrence.title,
    amount: @recurrence.amount,
    transaction_type: @recurrence.transaction_type,
    payment_method: @recurrence.payment_method,
    occurred_at: @target_date.to_time.middle_of_day
  )
```

### Impact Analysis
- Introduced: 2026-10-17 (Architecture & Product Specification baseline)
- Affects: 6 modules (`AUTH`, `WEB`, `TXN`, `AGG`, `REC`, `DATA`)
- Recent themes: "multi-tenancy lógico", "isolamento de dados", "Current.user", "HTTP 404 Not Found"

### Alternatives (if observable)
- Returning `HTTP 403 Forbidden` on cross-tenant access was implicitly rejected by `PRD-001.md` RF-002 because `403` allows an attacker to deduce that a record with the requested ID exists for another user.

## Questions to Address in ADR (if created)

- Why was shared-schema logical multi-tenancy via Rails association scoping chosen over PostgreSQL Row-Level Security (RLS) or gem-based global scoping (`acts_as_tenant` / `default_scope`)?
- Why was `default_scope` avoided in favor of explicit `@user.transactions` and `Current.user` association chaining?
- How will automated tests or static analysis (e.g., RuboCop / Brakeman) verify that no controller or service introduces unscoped model queries?
- Under what conditions (if any) would a future administrative or support role bypass `Current.user` scoping?

## Related Potential ADRs
- [Stateful Session-Based Authentication with Rails `has_secure_password` (`bcrypt`)](./stateful-session-authentication-with-bcrypt.md)

## Additional Notes
- Note that `recurrence_executions` does not have a direct `user_id` column in `docs/tech_spec.md`; its tenant isolation is derived transitively through its `NOT NULL` foreign keys to `recurrences(id)` and `transactions(id)`.
