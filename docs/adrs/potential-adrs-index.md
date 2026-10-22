# Potential ADRs Index

## Analysis Progress
### Analyzed Modules
- **WEB**: Web & Reactive UI Layer - 2026-10-18 - 1 high, 1 medium ADRs
- **AUTH**: Identity & Multi-Tenant Access - 2026-10-18 - 2 high, 0 medium ADRs
- **TXN**: Effective Transactions Management - 2026-10-18 - 1 high, 1 medium ADRs
- **AGG**: Financial Consolidation & Dashboard Aggregation - 2026-10-18 - 1 high, 1 medium ADRs
- **REC**: Recurrence Engine & Idempotent Execution - 2026-10-18 - 2 high, 0 medium ADRs
- **ASYNC**: Background Scheduling & Workers - 2026-10-18 - 1 high, 1 medium ADRs
- **DATA**: Relational Persistence & Schema Integrity - 2026-10-18 - 1 high, 0 medium ADRs

### Pending Analysis
*(None — All 7 mapped modules have been analyzed)*

---

## High Priority ADRs (`must-document/`)

### Module: WEB
| Title | Category | Score | File |
|-------|----------|-------|------|
| Server-Driven Reactive UI with Rails 8 and Hotwire | Architecture / Technology | 150 | [Link](./potential-adrs/must-document/WEB/server-driven-reactive-ui-with-rails-8-and-hotwire.md) |

### Module: AUTH
| Title | Category | Score | File |
|-------|----------|-------|------|
| Logical Multi-Tenancy via Current.user Association Scoping and HTTP 404 Indistinguishability | Security | 145 | [Link](./potential-adrs/must-document/AUTH/logical-multi-tenancy-with-current-user-scoping-and-404-indistinguishability.md) |
| Stateful Session-Based Authentication with Rails has_secure_password (bcrypt) and Dual-Identifier Credentials | Security | 120 | [Link](./potential-adrs/must-document/AUTH/stateful-session-authentication-with-bcrypt.md) |

### Module: TXN
| Title | Category | Score | File |
|-------|----------|-------|------|
| Decoupled Materialized Financial Transaction Facts | Architecture | 135 | [Link](./potential-adrs/must-document/TXN/decoupled-materialized-transaction-facts.md) |

### Module: AGG
| Title | Category | Score | File |
|-------|----------|-------|------|
| Dynamic Balance Derivation Without Static Balance State | Architecture | 135 | [Link](./potential-adrs/must-document/AGG/dynamic-balance-derivation-without-static-balance-state.md) |

### Module: REC
| Title | Category | Score | File |
|-------|----------|-------|------|
| Decoupling Generated Transactions from Recurrence Rules | Architecture | 125 | [Link](./potential-adrs/must-document/REC/decoupled-generated-transactions-from-recurrence-rules.md) |
| Database-Enforced Idempotency via RecurrenceExecution Audit Table | Architecture | 125 | [Link](./potential-adrs/must-document/REC/database-enforced-idempotency-via-recurrence-execution.md) |

### Module: ASYNC
| Title | Category | Score | File |
|-------|----------|-------|------|
| Asynchronous Job Processing with Redis 7 and Sidekiq 7 | Technology | 130 | [Link](./potential-adrs/must-document/ASYNC/asynchronous-job-processing-with-redis-and-sidekiq.md) |

### Module: DATA
| Title | Category | Score | File |
|-------|----------|-------|------|
| PostgreSQL 16 as Authoritative ACID Datastore with Defense-in-Depth CHECK Constraints and Composite Indexing | Technology / Architecture / Performance | 150 | [Link](./potential-adrs/must-document/DATA/postgresql-16-authoritative-acid-datastore-with-check-constraints-and-composite-indexing.md) |

---

## Medium Priority ADRs (`consider/`)

### Module: WEB
| Title | Category | Score | File |
|-------|----------|-------|------|
| Thin Controllers with Stateless Domain Service Objects | Architecture | 75 | [Link](./potential-adrs/consider/WEB/thin-controllers-with-stateless-domain-service-objects.md) |

### Module: TXN
| Title | Category | Score | File |
|-------|----------|-------|------|
| Unsigned Fixed-Point Monetary Model with Dual-Layer Invariant Enforcement | Architecture | 95 | [Link](./potential-adrs/consider/TXN/unsigned-monetary-model-with-dual-layer-invariants.md) |

### Module: AGG
| Title | Category | Score | File |
|-------|----------|-------|------|
| In-Database SQL Pushdown Aggregation with Bounded Temporal Window | Performance | 90 | [Link](./potential-adrs/consider/AGG/in-database-sql-pushdown-aggregation-with-bounded-temporal-window.md) |

### Module: ASYNC
| Title | Category | Score | File |
|-------|----------|-------|------|
| Fan-Out Cron Scheduling Pattern for Recurring Transactions | Architecture | 95 | [Link](./potential-adrs/consider/ASYNC/fan-out-cron-scheduling-for-recurring-transactions.md) |

---

## Summary
- **High Priority (`must-document/`)**: 9 ADRs
- **Medium Priority (`consider/`)**: 4 ADRs
- **Total**: 13 Potential ADRs
- **Modules Analyzed**: 7 of 7 (`WEB`, `AUTH`, `TXN`, `AGG`, `REC`, `ASYNC`, `DATA`)
