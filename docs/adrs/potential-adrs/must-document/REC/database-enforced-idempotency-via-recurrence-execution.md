# Potential ADR: Database-Enforced Idempotency via RecurrenceExecution Audit Table

**Module**: REC
**Category**: Architecture
**Priority**: Must Document (Score: 125)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

⚠️ **SIMILAR DECISION EXISTS IN HLD SUMMARY**

This decision corresponds directly to an architectural decision summarized in `docs/HLD-001.md` and required by `docs/PRD-001.md`:
- **ADR-004 (HLD-001.md)**: *Idempotência de Background via Banco Relacional* — Guarantee background job idempotency through a composite unique index on `(recurrence_id, scheduled_for)` in the `recurrence_executions` table to prevent duplicate transactions under network retries or worker concurrency.
- **RF-005 (PRD-001.md)**: *Geração Idempotente de Recorrências* — Execution failures or retries must never duplicate postings for the same recurrence cycle (strictly zero duplication rate).

**Recommended Actions**:
- Formalize `ADR-004` into a complete MADR document under `docs/adrs/generated/`.
- Document both the relational schema constraint (`uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)`) and the optimistic exception-handling pattern (`rescue ActiveRecord::RecordNotUnique`) in `RecurrenceExecutionService`.

---

## What Was Identified

The `REC` module (`Recurrence Engine & Idempotent Execution`) is invoked asynchronously by Sidekiq background workers (`RecurrenceSchedulerWorker` and `RecurrenceWorker`), which operate under **at-least-once delivery semantics**. Because network partitions, Redis timeouts, worker restarts, or overlapping cron schedules can cause the same `(recurrence_id, target_date)` job payload to be executed multiple times concurrently or sequentially, the system enforces strict idempotency at the PostgreSQL relational database layer rather than relying on application-level pre-checks (`SELECT` before `INSERT`) or distributed Redis locks.

Specifically, `RecurrenceExecutionService` wraps the creation of the `Transaction` record and the insertion of a `RecurrenceExecution` audit record inside a single ACID database transaction (`ActiveRecord::Base.transaction`). The `recurrence_executions` table defines a composite unique constraint `CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)`. If a duplicate or concurrent worker attempts to materialize the same `(recurrence_id, scheduled_for)` cycle, PostgreSQL immediately aborts the transaction with a unique constraint violation, automatically rolling back the `Transaction.create!` insert. `RecurrenceExecutionService` rescues `ActiveRecord::RecordNotUnique`, logs an informational message, and returns `nil` cleanly so Sidekiq marks the duplicate job as completed without retrying.

## Why This Might Deserve an ADR

- **Impact**: Guarantees a strictly zero duplicate transaction rate (a primary business acceptance criterion in `PRD-001.md`) across `[REC]`, `[ASYNC]`, `[TXN]`, and `[DATA]`.
- **Trade-offs**: Relies on database exception handling (`ActiveRecord::RecordNotUnique`) and transaction rollbacks under contention rather than in-memory distributed locking (e.g., Redlock or Sidekiq Enterprise unique jobs). While an aborted insert consumes a sequence ID in `transactions_id_seq` on collision, collisions only occur during rare retry/race conditions, and relational unique constraints provide mathematical ACID certainty that Redis locks cannot guarantee if lock TTLs expire.
- **Complexity**: Combines relational DDL constraints (`uq_recurrence_cycle`), ACID transaction boundaries, and optimistic concurrency control in `RecurrenceExecutionService`. Importantly, keying idempotency on `(recurrence_id, scheduled_for: DATE)` in `recurrence_executions` rather than `(recurrence_id, occurred_at: TIMESTAMPTZ)` on `transactions` prevents idempotency bypass if a user later edits the `occurred_at` timestamp of a generated transaction.
- **Team Knowledge**: Essential for any developer modifying `RecurrenceExecutionService`, `RecurrenceSchedulerWorker`, or `RecurrenceWorker`. Engineers must understand why `create!` is called inside a single transaction without a prior `.exists?` check (or why a `.exists?` check alone is vulnerable to TOCTOU race conditions) and why `ActiveRecord::RecordNotUnique` is swallowed rather than re-raised to Sidekiq.
- **Future Implications**: Establishes a reusable pattern for idempotent background consumers across the monolith without requiring commercial job-uniqueness gems.
- **Temporal Context**: Foundational concurrency invariant defined in baseline specifications (`HLD-001.md` v1.1.0, `tech_spec.md` v1.0.0 — 2026-10-17).

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#L57-L84) - Lines 57-84
  - Defines `RecurrenceExecution` as the technical audit record acting as an idempotency key between `Recurrence` and the scheduled cycle date (`ADR-004`).
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L63-L71) - Lines 63-71
  - Defines the `recurrence_executions` table and `CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)`.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md#L138-L175) - Lines 138-175
  - Provides the complete implementation of `RecurrenceExecutionService` showing the atomic `ActiveRecord::Base.transaction` block and silent idempotency handling via `rescue ActiveRecord::RecordNotUnique`.
- [`docs/PRD-001.md`](../../../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md#L48-L59) - Lines 48-59
  - Mandates `RF-005: Geração Idempotente de Recorrências` and the business acceptance criterion: *"Taxa de duplicidade na geração de transações recorrentes é estritamente zero."*

### Code Evidence
```sql
-- Example from docs/tech_spec.md:63-70
CREATE TABLE recurrence_executions (
    id BIGSERIAL PRIMARY KEY,
    recurrence_id BIGINT NOT NULL REFERENCES recurrences(id) ON DELETE CASCADE,
    transaction_id BIGINT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    scheduled_for DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)
);
```

```ruby
# Example from docs/tech_spec.md:143-174
class RecurrenceExecutionService
  def self.call(recurrence:, target_date:)
    new(recurrence, target_date).call
  end

  def initialize(recurrence, target_date)
    @recurrence = recurrence
    @target_date = target_date
  end

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
- Introduced: 2026-10-17 (Specification baseline in `HLD-001.md` and `tech_spec.md`)
- Affects: 4 modules (`REC`, `ASYNC`, `TXN`, `DATA`)
- Recent themes: Concurrency control, at-least-once Sidekiq job execution, relational idempotency key

### Alternatives (if observable)
- **Unique Constraint on `transactions(recurrence_id, occurred_at)`**: Depicted in [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md#L74), where idempotency is checked against `(recurrence_id, occurred_at)` directly on `TRANSACTION` (`IdempCheck{"Transação Existe?"}` in Diagram 5). Moving the constraint to `recurrence_executions(recurrence_id, scheduled_for)` in `tech_spec.md` is superior because `scheduled_for` is an immutable `DATE` representing the recurrence cycle, whereas `transactions.occurred_at` is a user-editable `TIMESTAMP WITH TIME ZONE` (`middle_of_day`).
- **Application-Level Pre-Check (`SELECT` before `INSERT`)**: Illustrated conceptually in Diagram 5 of `sqr-finance-diagrams.md`; while `RecurrenceSchedulerWorker` filters out already-processed cycles when enqueuing jobs, relying solely on a pre-check in the worker is vulnerable to race conditions when two workers run simultaneously, necessitating the database-level `UNIQUE` constraint and `RecordNotUnique` rescue.

## Questions to Address in ADR (if created)

- Why is idempotency enforced via a PostgreSQL `UNIQUE (recurrence_id, scheduled_for)` constraint on `recurrence_executions` rather than Redis locks or application-level `.exists?` checks?
- Why is `scheduled_for` (`DATE`) tracked on a dedicated `recurrence_executions` table instead of using `(recurrence_id, occurred_at)` on `transactions`?
- What happens if `Transaction` creation raises a validation error vs. `RecurrenceExecution` raising `ActiveRecord::RecordNotUnique`?
- How does `RecurrenceSchedulerWorker` use `recurrence_executions` to query only unprocessed eligible cycles before enqueuing `RecurrenceWorker` jobs?

## Related Potential ADRs
- [`decoupled-generated-transactions-from-recurrence-rules.md`](./decoupled-generated-transactions-from-recurrence-rules.md) (Module `REC` — `ADR-002`)

## Additional Notes
- Ensure that when `RecurrenceExecutionService` is implemented in Rails, `RecurrenceExecution.create!` is the only unique-constrained operation inside the transaction block that can raise `ActiveRecord::RecordNotUnique`, so unrelated unique constraint errors (if any were ever added to `transactions`) are not accidentally masked.
