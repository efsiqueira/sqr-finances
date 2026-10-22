# Potential ADR: Fan-Out Cron Scheduling Pattern for Recurring Transactions

**Module**: ASYNC
**Category**: Architecture
**Priority**: Consider (Score: 95)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

ℹ️ **RELATED DECISIONS**

This decision relates to existing decisions documented in `docs/HLD-001.md`:
- **ADR-004**: Idempotência de Background via Banco Relacional (`DATA` / `REC`, 2026-10-17, Status: Accepted) — Common keywords: `recurrence`, `scheduled_for`, `background`, `worker`, `idempotency` (~50% keyword overlap)
- **ADR-002**: Desacoplamento de Transações Geradas (`REC` / `TXN`, 2026-10-17, Status: Accepted)

**Timeline Context**:
- Defined alongside `ADR-002` and `ADR-004` in `docs/HLD-001.md` and `docs/tech_spec.md` (2026-10-17).
- Complements `ADR-004` by defining *how* work is partitioned, scheduled, and dispatched into atomic `(recurrence_id, target_date)` units before hitting the relational idempotency constraint.

**When creating formal ADR**: Reference `ADR-004` and the Redis/Sidekiq infrastructure ADR in the Related ADRs section.

---

## What Was Identified

The `ASYNC` module implements a **two-stage Fan-Out Scheduler/Worker pattern** to materialize recurring transactions (`RF-004`, `RF-005`). Instead of a single monolithic cron job iterating over all active recurrences and inserting transactions sequentially in one long-running process, the architecture splits responsibility between:
1. **`RecurrenceSchedulerWorker`** (Dispatcher): Triggered daily at `00:05 UTC` by **Sidekiq Cron**. It queries active recurrence rules (`Recurrence.where(active: true)`), calculates all eligible unprocessed cycle dates up to the current date (allowing retroactive catch-up if a previous run was missed), and enqueues an individual job per cycle.
2. **`RecurrenceWorker`** (Consumer): Receives a fine-grained tuple of `(recurrence_id, target_date)` from the Redis queue and delegates atomic execution to `RecurrenceExecutionService.call`.

This pattern was specified on 2026-10-17 in `docs/tech_spec.md` and `docs/mermaid/sqr-finance-diagrams.md` to ensure fault isolation, retroactive catch-up resilience, and horizontal scalability across Sidekiq worker threads.

## Why This Might Deserve an ADR

- **Impact**: Governs the execution topology, failure blast radius, and catch-up behavior of the recurrence engine across `ASYNC` and `REC`.
- **Trade-offs**: Fanning out one job per `(recurrence_id, target_date)` increases Redis queue message volume compared to batch processing, but isolates failures to a single user/cycle so one failing recurrence never blocks or aborts other users' recurring transactions.
- **Complexity**: Requires coordination between the scheduler's eligibility query ("each eligible unprocessed cycle up to the current date") and the worker's idempotent execution (`RecurrenceExecutionService`), as well as timezone boundary handling around `00:05 UTC`.
- **Team Knowledge**: Engineers modifying recurrence rules (`weekly`, `monthly`, `yearly`) or debugging missed/delayed cycles must understand how `RecurrenceSchedulerWorker` discovers unprocessed historical cycles and fans them out to `RecurrenceWorker`.
- **Future Implications**: Enables parallel consumption across multiple Sidekiq worker threads/containers as the user base grows without changing the domain service contract.
- **Temporal Context**: Core scheduling design specified on 2026-10-17 (`tech_spec.md` v1.0.0).

## Evidence Found in Codebase

### Key Files
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 138–175, 200–203
  - Defines `RecurrenceSchedulerWorker` (`00:05 UTC` daily sweep and per-cycle job fan-out), `RecurrenceWorker` (`(recurrence_id, target_date)` consumer), and `RecurrenceExecutionService`.
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 245–294
  - Illustrates the end-to-end flow from `Sidekiq Cron` through retroactive cycle evaluation, idempotency checks, transaction creation, and rule deactivation upon reaching `end_date`.
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Line 47
  - Documents `Sidekiq Cron & Workers` as the daily scheduler that scans eligible recurrences and executes idempotent background generation.

### Code Evidence
```markdown
// From docs/tech_spec.md:200-203
## 4. Background Workers (Sidekiq)

- **`RecurrenceSchedulerWorker`**: Roda diariamente via Sidekiq Cron (às 00:05 UTC). Varre `Recurrence.where(active: true)` e enfileira um job para cada ciclo elegível não processado até a data atual.
- **`RecurrenceWorker`**: Recebe `(recurrence_id, target_date)` e executa `RecurrenceExecutionService.call`.
```

```ruby
# From docs/tech_spec.md:143-174 (Downstream consumer invoked per fan-out job)
class RecurrenceExecutionService
  def self.call(recurrence:, target_date:)
    new(recurrence, target_date).call
  end
...
  def call
    ActiveRecord::Base.transaction do
      transaction = @recurrence.user.transactions.create!(
        title: @recurrence.title,
        amount: @recurrence.amount,
        transaction_type: @recurrence.transaction_type,
        payment_method: @recurrence.payment_method,
        occurred_at: @target_date.to_time.middle_of_day
      )

      RecurrenceExecution.create!(
        recurrence: @recurrence,
        transaction: transaction,
        scheduled_for: @target_date
      )
    end
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("Recurrence ##{@recurrence.id} for #{@target_date} already executed.")
    nil
  end
end
```

### Impact Analysis
- Introduced: 2026-10-17 (`docs/tech_spec.md` v1.0.0)
- Affects: 2 modules (`ASYNC`, `REC`) and 4 key components (`RecurrenceSchedulerWorker`, `RecurrenceWorker`, `RecurrenceProcessorService`, `RecurrenceExecutionService`)
- Recent themes: "daily cron sweep at 00:05 UTC", "per-cycle job fan-out", "retroactive cycle catch-up"

### Alternatives (if observable)
- **Monolithic Cron Batch Job**: Processing all due recurrences synchronously inside a single daily job without fanning out to `RecurrenceWorker` (rejected implicitly in `tech_spec.md` in favor of isolating each `(recurrence_id, target_date)` execution in `RecurrenceWorker`).

## Questions to Address in ADR (if created)

- How does `RecurrenceSchedulerWorker` batch database reads (e.g., `find_each`) and Redis enqueuing (`perform_bulk`) when scanning `Recurrence.where(active: true)` at scale?
- How does running the cron at `00:05 UTC` interact with users in Brazilian timezones (`America/Sao_Paulo`, UTC-3), where `00:05 UTC` is `21:05` on the previous calendar day?
- What is the maximum retroactive lookback window if a user creates a recurrence with a past `start_date` or if the scheduler recovers from downtime?

## Related Potential ADRs
- [Asynchronous Job Processing with Redis 7 and Sidekiq 7](../../must-document/ASYNC/asynchronous-job-processing-with-redis-and-sidekiq.md)
- `ADR-004: Idempotência de Background via Banco Relacional` (documented in `docs/HLD-001.md`)

## Additional Notes
- Notice a subtle timezone consideration in `tech_spec.md`: `RecurrenceSchedulerWorker` runs at `00:05 UTC`, and `RecurrenceExecutionService` sets `occurred_at: @target_date.to_time.middle_of_day`. Documenting timezone alignment in the formal ADR will prevent premature previous-evening execution for UTC-3 users.
