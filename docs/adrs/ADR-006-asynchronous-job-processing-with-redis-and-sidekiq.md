# ADR-006: Asynchronous Job Processing with Redis 7, Sidekiq 7 and Sidekiq Cron

- **Status:** Accepted
- **Date:** 2026-10-24
- **Module:** `[ASYNC]`
- **Category:** Technology / Architecture
- **Deciders:** Sqr Finances Core Architecture Team
- **Related ADRs:**
  - [ADR-002: Desacoplamento de Transações Geradas e Preservação de Histórico (`REC` / `TXN`)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)
  - [ADR-004: Idempotência de Background via Banco Relacional (`REC` / `DATA`)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)
  - [ADR-005: PostgreSQL 16 as Authoritative ACID Datastore (`DATA`)](./ADR-005-postgresql-16-authoritative-acid-datastore.md)

---

## 1. Context and Problem Statement

Sqr Finances requires periodic, autonomous background processing to fulfill requirement **RF-005** (automatic and idempotent materialization of recurring financial transactions across weekly, monthly, and yearly cycles). Recurring transaction generation must run independently from synchronous HTTP/Hotwire request-response cycles to avoid web request latency degradation, connection timeouts, and request thread starvation.

In a modern Rails 8 application, several background processing architectures are available:
1. In-process database-backed queueing (Rails 8 default **Solid Queue**, GoodJob, Delayed::Job) backed by PostgreSQL.
2. In-memory message brokers and distributed task runners (**Redis 7 + Sidekiq 7**).
3. Cloud-managed queues (AWS SQS, Google Cloud Tasks).

The key architectural challenge is ensuring that:
- Daily cron scheduling (e.g. at `00:05 UTC`) reliably triggers fan-out processing across all active user recurrences.
- Worker concurrency executes with low latency, predictable thread safety, and isolated queue prioritization (`critical`, `default`, `low`).
- Infrastructure remains fully containerized and testable in local development via Docker Compose while adhering to strict at-least-once delivery semantics coupled with relational idempotency (`ADR-004`).

---

## 2. Decision Drivers

- **High-Throughput and Low Latency**: Minimize database connection contention on the primary transactional datastore (PostgreSQL 16) during massive batch processing cycles.
- **Battle-Tested Cron Scheduling**: Native support for declarative, dynamic cron schedules (`sidekiq-cron`) loaded on process startup without requiring external OS crontab dependencies or third-party daemon wrappers.
- **Resource Isolation**: Separate queue workloads across distinct priorities (`critical`, `default`, `low`) and configure concurrency levels explicitly (5 concurrent threads per worker process).
- **Zero Lock Contention on Primary Database**: Prevent polling overhead and transaction lock churn on PostgreSQL tables that occur with relational database queue backends.
- **Clear Operational Model**: Straightforward integration with local container orchestration (`docker-compose.yml`) and process managers (`Procfile.dev`).

---

## 3. Considered Options

1. **Redis 7 + Sidekiq 7 + Sidekiq Cron (Chosen)**
2. **Solid Queue (Rails 8 Default PostgreSQL Queue)**
3. **GoodJob (PostgreSQL Advisory Locks Queue)**
4. **Cloud Managed Queues (AWS SQS / Cloud Tasks via ActiveJob)**

---

## 4. Decision

We chose **Redis 7** as the dedicated in-memory data store and message broker paired with **Sidekiq 7** and **Sidekiq Cron (1.12+)** as the primary asynchronous processing engine for Sqr Finances.

Specifically, the architecture establishes the following configuration and operational standards:

### 4.1 Queue Topology and Concurrency (`config/sidekiq.yml`)
Worker processes run with a defined concurrency of 5 threads and process three prioritized queues:
```yaml
:concurrency: 5
:queues:
  - critical
  - default
  - low
```
- `critical`: High-priority operational jobs and security tasks.
- `default`: Scheduled recurrence materialization workers (`RecurrenceWorker`, `RecurrenceSchedulerWorker`).
- `low`: Non-blocking maintenance, diagnostic cleanup, and analytical cache warming.

### 4.2 Declarative Cron Scheduling (`config/schedule.yml`)
Daily recurring checks are managed through `Sidekiq Cron`, configured in `config/initializers/sidekiq.rb` to load during Sidekiq server startup (`on(:startup)`). The schedule is declared in `config/schedule.yml`, enabling version-controlled, reproducible scheduling without manual database seeding or host-level cron files.

### 4.3 Native Sidekiq API and ActiveJob Interoperability
- Critical performance-sensitive background workers (such as recurrence processors) directly include `Sidekiq::Job` for explicit control over retry policies, queue selection, and dead-letter handling.
- `config.active_job.queue_adapter = :sidekiq` is configured in Rails, allowing framework-level components (ActionMailer, ActiveStorage) to transparently route through Sidekiq.

### 4.4 Parameter Serialization & Idempotency Boundary
Following Sidekiq best practices and `ADR-004`:
- Job payloads must only accept JSON-safe primitive types (`Integer`, `String`), such as `(recurrence_id, target_date)`. Complex ActiveRecord objects are never serialized into Redis.
- Because Sidekiq operates under **at-least-once delivery semantics**, all jobs must be strictly idempotent. Concurrency conflicts and duplicate executions are safely absorbed at the database level via PostgreSQL unique constraints (`uq_recurrence_cycle` on `recurrence_executions`).

### 4.5 Testing Isolation (`spec/support/sidekiq.rb`)
In RSpec test suites, jobs are processed in memory using `Sidekiq::Testing.fake!` or `.inline!`, with queues automatically purged (`Sidekiq::Worker.clear_all`) before each test example to ensure zero cross-test state leakage.

---

## 5. Consequences

### Positive
- **Offloaded PostgreSQL Load**: No polling table queries, lock contention, or deadlocks on PostgreSQL for job coordination.
- **Predictable Latency**: Sub-millisecond queue enqueuing and instant pop operations via Redis in-memory data structures.
- **Rich Ecosystem & UI**: Comprehensive observability, introspection tools, and mature retry/dead-set inspection capabilities.
- **Decoupled Architecture**: Background workers scale horizontally in independent containerized worker instances without impacting web server response times.

### Negative / Trade-offs
- **Additional Stateful Service**: Requires provisioning and monitoring a dedicated Redis 7 container alongside PostgreSQL 16.
- **Memory Bound**: Redis stores job queues in RAM, requiring appropriate memory ceilings and persistence policies (RDB snapshots / AOF) in production.
- **Requires Strict Idempotency**: Due to network partitions or worker termination during execution, jobs may execute multiple times; application services must defensively handle duplicates as mandated in `ADR-004`.
