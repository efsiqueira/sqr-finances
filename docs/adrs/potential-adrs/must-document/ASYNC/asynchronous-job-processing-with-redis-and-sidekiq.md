# Potential ADR: Asynchronous Job Processing with Redis 7 and Sidekiq 7

**Module**: ASYNC
**Category**: Technology
**Priority**: Must Document (Score: 130)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

ℹ️ **RELATED DECISIONS**

This decision relates to foundational architectural decisions documented in `docs/HLD-001.md`:
- **ADR-004**: Idempotência de Background via Banco Relacional (`DATA` / `REC`, 2026-10-17, Status: Accepted) — Common keywords: `sidekiq`, `background`, `jobs`, `workers`, `retries`, `concurrency`, `idempotency` (~55% keyword overlap)
- **ADR-002**: Desacoplamento de Transações Geradas (`REC` / `TXN`, 2026-10-17, Status: Accepted)

**Timeline Context**:
- Introduced concurrently with `ADR-004` in `docs/HLD-001.md` (v1.1.0, 2026-10-17) and `docs/tech_spec.md` (v1.0.0, 2026-10-17).
- `ADR-004` addresses the *relational idempotency mechanism* (`UNIQUE (recurrence_id, scheduled_for)` on `recurrence_executions`), whereas this potential ADR captures the *infrastructure and runtime choice* of adopting **Redis 7 + Sidekiq 7** (with `sidekiq-cron`) over Rails 8's default database-backed `Solid Queue` or other queueing backends.

**When creating formal ADR**: Reference `ADR-004` and `ADR-002` in the Related ADRs section.

---

## What Was Identified

Sqr Finance adopts **Redis 7** as an in-memory data store and message broker paired with **Sidekiq 7** and **Sidekiq Cron** as the dedicated asynchronous background processing engine for the modular Rails 8 monolith. Rather than executing periodic transaction generation within the web server process or using a relational database queue, the architecture provisions an independent Redis 7 instance and dedicated Sidekiq worker processes to handle scheduled and queued workloads outside the synchronous HTTP/Hotwire request cycle.

This architectural pattern was established in the baseline architecture specification (`docs/HLD-001.md` and `docs/tech_spec.md`, dated 2026-10-17) to fulfill requirement `RF-005` (automatic and idempotent generation of recurring financial transactions). Because Sidekiq operates with at-least-once delivery semantics and multi-threaded worker concurrency, this infrastructure decision directly motivates database-enforced idempotency (`ADR-004`).

## Why This Might Deserve an ADR

- **Impact**: Introduces an additional stateful infrastructure dependency (Redis 7) alongside PostgreSQL 16 and requires running separate Sidekiq worker processes in production and development environments.
- **Trade-offs**: Although Ruby on Rails 8 ships with `Solid Queue` (which uses PostgreSQL as the job queue backend and eliminates Redis for many monoliths), choosing Redis 7 + Sidekiq 7 trades higher operational and infrastructure complexity for battle-tested throughput, mature cron scheduling (`sidekiq-cron`), low-latency in-memory queuing, and established retry/dead-letter queue semantics.
- **Complexity**: Multi-threaded Sidekiq workers and automatic network/process retries introduce concurrency and duplicate-delivery edge cases that require strict thread safety and transactional idempotency in downstream domain services (`RecurrenceExecutionService`).
- **Team Knowledge**: Every engineer must understand that background jobs in Sqr Finance follow at-least-once delivery, must serialize only primitive identifiers (`recurrence_id`, `target_date`), and must be strictly idempotent.
- **Future Implications**: Provides ready-made Redis 7 infrastructure for future caching, rate-limiting, or ActionCable/Turbo Stream broadcasts if real-time background push notifications are needed beyond the MVP.
- **Temporal Context**: Baseline architectural decision established on 2026-10-17 (`HLD-001.md` v1.1.0), designed as a long-term foundational component.

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Lines 12, 28–36, 47, 82–84
  - Defines the high-level topology integrating Rails 8, Redis 7, Sidekiq Workers, and PostgreSQL 16, and specifies the responsibility of `Sidekiq Cron & Workers`.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 5, 143–174, 200–203
  - Declares `Sidekiq 7` in the core stack and specifies `RecurrenceSchedulerWorker` and `RecurrenceWorker`.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 16, 178–200, 245–294
  - Models the `AsyncLayer` (`Sidekiq Cron` -> `Redis Queue` -> `Sidekiq Workers`) and the idempotent processing flowchart.

### Code Evidence
```markdown
// From docs/HLD-001.md:12-36
A solução adota uma topologia monolítica moderna baseada em **Ruby on Rails 8**, utilizando **PostgreSQL** como fonte primária e autoritativa de verdade (ACID) e **Redis + Sidekiq** para processamento assíncrono em segundo plano.
...
        ┌──────────────────────┐        ┌──────────────────────┐
        │   Redis 7 (Sidekiq)  │        │   Domain Services    │
        └──────────┬───────────┘        └──────────┬───────────┘
                   │                               │
                   ▼                               ▼
        ┌──────────────────────┐        ┌──────────────────────┐
        │    Sidekiq Worker    ├───────►│    PostgreSQL 16     │
        │ (Geração Recorrente) │  ACID  │ (Transações / Chaves)│
        └──────────────────────┘        └──────────────────────┘
```

```markdown
// From docs/tech_spec.md:200-203
## 4. Background Workers (Sidekiq)

- **`RecurrenceSchedulerWorker`**: Roda diariamente via Sidekiq Cron (às 00:05 UTC). Varre `Recurrence.where(active: true)` e enfileira um job para cada ciclo elegível não processado até a data atual.
- **`RecurrenceWorker`**: Recebe `(recurrence_id, target_date)` e executa `RecurrenceExecutionService.call`.
```

### Impact Analysis
- Introduced: 2026-10-17 (Specification baseline in `docs/HLD-001.md` and `docs/tech_spec.md`)
- Affects: 2 planned worker files (`app/workers/recurrence_scheduler_worker.rb`, `app/workers/recurrence_worker.rb`), infrastructure provisioning (`Redis 7`), and 3 modules (`ASYNC`, `REC`, `DATA`)
- Recent themes: "idempotent background processing", "recurrence materialization", "modular monolith topology"

### Alternatives (if observable)
- Not explicitly contrasted in documentation, though choosing Redis 7 + Sidekiq 7 in a **Rails 8.0** greenfield monolith notably bypasses Rails 8's default database-backed `Solid Queue` in favor of a dedicated Redis-backed worker topology.

## Questions to Address in ADR (if created)

- Why was Redis 7 + Sidekiq 7 selected over PostgreSQL-backed queuing alternatives (such as Rails 8 default `Solid Queue` or `GoodJob`) that would avoid operating a separate Redis cluster?
- What retry policy, dead-letter queue (`DeadSet`) retention, and concurrency settings should be configured for Sidekiq workers?
- How is Redis persistence (RDB/AOF) configured to prevent lost jobs if the Redis instance restarts between `00:05 UTC` scheduling and worker execution?
- Will Sidekiq be accessed directly (`Sidekiq::Worker` / `Sidekiq::Job`) or abstracted behind Rails `ActiveJob`?

## Related Potential ADRs
- [Fan-Out Cron Scheduling Pattern for Recurring Transactions](../../consider/ASYNC/fan-out-cron-scheduling-for-recurring-transactions.md)
- `ADR-004: Idempotência de Background via Banco Relacional` (documented in `docs/HLD-001.md`)

## Additional Notes
- Because the repository is currently in the specification phase, `app/workers/recurrence_scheduler_worker.rb` and `app/workers/recurrence_worker.rb` are specified in `docs/tech_spec.md` but not yet generated on disk.
