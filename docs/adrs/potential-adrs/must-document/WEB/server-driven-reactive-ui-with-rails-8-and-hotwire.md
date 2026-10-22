# Potential ADR: Server-Driven Reactive UI with Rails 8 and Hotwire

**Module**: WEB
**Category**: Architecture / Technology
**Priority**: Must Document (Score: 150)
**Date Identified**: 2026-10-18

---

## Existing ADR Context

⚠️ **SIMILAR DECISION EXISTS IN HLD SUMMARY**

This decision is explicitly summarized in the High-Level Design document:
- **ADR-003 (in `docs/HLD-001.md`)**: Arquitetura Orientada ao Servidor (Hotwire) (90% keyword match)
  - Module: WEB, Date: 2026-10-17, Status: Accepted (in HLD-001 v1.1.0)
  - Common keywords: rails 8, hotwire, turbo frames, turbo streams, stimulus, server-driven ui, spa

**Timeline**: Documented on 2026-10-17 in `docs/HLD-001.md` and `docs/tech_spec.md` during the greenfield specification phase.

**Recommended Actions**:
- Promote the summary entry `ADR-003` from `docs/HLD-001.md` into a full formal MADR document in `docs/adrs/generated/` covering the concrete Turbo Frame contracts and multi-target Turbo Stream mutation patterns specified in `docs/tech_spec.md`.

---

## What Was Identified

Sqr Finance adopts a **Server-Driven Reactive UI architecture** built on **Ruby on Rails 8.0** and the **Hotwire** suite (**Turbo Drive, Turbo Frames, Turbo Streams, and Stimulus JS**), deliberately eschewing a decoupled Single-Page Application (SPA) frontend (such as React, Vue, or Angular) and a separate JSON serialization API layer. Instead of maintaining duplicated state machines, validation schemas, and routing tables across client and server repositories, the Rails application server acts as the single authoritative renderer of UI state over HTTPS (`text/html` and `text/vnd.turbo-stream.html`).

At the interface contract level, the dashboard view is partitioned into three isolated **Turbo Frame** boundaries: `dashboard_metrics` (displaying Consolidated Period Income, Period Expense, Net Period Result, and Historical Accumulated Balance), `transactions_list` (displaying the chronological ledger filtered by period), and `transaction_form_container` (housing the rapid transaction entry modal/panel). Temporal navigation requests (`GET /dashboard?period=month`) target Turbo Frames directly to swap only the affected DOM subtrees without full-page reloads.

For write operations (`POST /transactions`), the server responds with a single atomic **Turbo Stream** payload (`app/views/transactions/create.turbo_stream.erb`) that executes three coordinated DOM mutations in one HTTP round-trip: prepending the newly created transaction row into `transactions_table_body`, replacing `dashboard_metrics` with freshly recalculated PostgreSQL aggregates, and resetting `transaction_form_container` with a clean `Transaction.new` form instance.

## Why This Might Deserve an ADR

- **Impact**: Defines the primary web framework (Rails 8.0) and client-server communication protocol (HTML over the wire via Hotwire) across 100% of user-facing workflows (`DashboardController`, `TransactionsController`, `RecurrencesController`, `SessionsController`).
- **Trade-offs**: Trades rich offline client-side state manipulation and native mobile JSON API reuse for zero API contract duplication, elimination of client-side financial rounding/state drift, and drastically lower cognitive and operational overhead.
- **Complexity**: Requires strict conventions around Turbo Frame IDs (`dashboard_metrics`, `transactions_list`, `transaction_form_container`) and multi-partial Turbo Stream responses so that ledger mutations and dashboard metric recalculations stay synchronized in a single response cycle.
- **Team Knowledge**: Every engineer implementing or modifying UI features must understand Turbo Frame scoping and Turbo Stream action semantics (`prepend`, `replace`, `update`) rather than writing custom `fetch`/JSON state reducers.
- **Future Implications**: Keeps the MVP deployment topology as a single unified Rails 8 web monolith; if a native mobile app is introduced post-MVP, either Strada/Hotwire Native can leverage the existing server-driven architecture or versioned JSON endpoints will need to be added alongside Turbo responses.
- **Temporal Context**: Foundational greenfield architecture decision established on 2026-10-17 (`HLD-001.md` v1.1.0, `tech_spec.md` v1.0.0).

## Evidence Found in Codebase

### Key Files
- [`docs/HLD-001.md`](../../../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md) - Lines 10-37, 44, 79-81
  - Defines the Modular Web Monolith topology with Rails 8 and Hotwire, the Web Layer component responsibility, and `ADR-003: Arquitetura Orientada ao Servidor (Hotwire)`.
- [`docs/tech_spec.md`](../../../../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md) - Lines 179-196
  - Specifies the Hotwire interface contracts, Turbo Frame identifiers (`dashboard_metrics`, `transactions_list`, `transaction_form_container`), and the reactive `POST /transactions` Turbo Stream template (`app/views/transactions/create.turbo_stream.erb`).
- [`docs/mermaid/sqr-finance-diagrams.md`](../../../../mermaid/sqr-finance-diagrams.md) - Lines 158-242, 297-336
  - Documents Component Architecture (Diagram 3) and Sequence Diagrams for reactive transaction creation via Turbo Streams (Diagram 4) and dashboard period filtering via Turbo Frames (Diagram 6).

### Code Evidence
```erb
<%# Specified in docs/tech_spec.md:191-196 — app/views/transactions/create.turbo_stream.erb %>
<%= turbo_stream.prepend "transactions_table_body", partial: "transactions/row", locals: { transaction: @transaction } %>
<%= turbo_stream.replace "dashboard_metrics", partial: "dashboard/metrics", locals: { metrics: @metrics } %>
<%= turbo_stream.update "transaction_form_container", partial: "transactions/form", locals: { transaction: Transaction.new } %>
```

```markdown
<!-- Specified in docs/HLD-001.md:79-81 -->
- **ADR-003: Arquitetura Orientada ao Servidor (Hotwire)**  
  *Decisão:* Utilizar Rails 8 com Hotwire sem SPA desacoplada.  
  *Motivação:* Reduz atrito cognitivo, simplifica a pilha tecnológica e entrega alta reatividade de interface.
```

### Impact Analysis
- Introduced: 2026-10-17 (Specification baseline in `docs/HLD-001.md` v1.1.0 and `docs/tech_spec.md` v1.0.0)
- Affects: All controllers, views, and Stimulus controllers in `[WEB]`, plus integration contracts with `[AUTH]`, `[TXN]`, `[AGG]`, and `[REC]`
- Recent themes: "Server-Driven UI", "Hotwire", "Turbo Streams", "Turbo Frames", "Modular Monolith"

### Alternatives (if observable)
- **Decoupled Single-Page Application (SPA) + REST/GraphQL API**: Explicitly rejected in `docs/HLD-001.md` (Lines 14, 79-81) and `docs/mermaid/sqr-finance-diagrams.md` (Line 161) due to the cognitive friction of maintaining separate frontend/backend stacks, duplicated validation/serialization contracts, and client-side state synchronization complexity for financial balances.

## Questions to Address in ADR (if created)

- How should validation errors on `POST /transactions` or `POST /recurrences` be rendered back into `transaction_form_container` (e.g., `HTTP 422 Unprocessable Entity` with `turbo_stream.replace` or frame-scoped form re-rendering)?
- When a user creates or deletes a transaction while viewing a custom date filter in `DashboardController`, how does `TransactionsController` preserve the active `[start_date, end_date]` filter context when re-computing `@metrics` for `turbo_stream.replace "dashboard_metrics"`?
- What boundaries govern when to use Stimulus JS controllers versus server-side Turbo Frame/Stream round-trips (e.g., toggling the `payment_method` field visibility when switching between `income` and `expense` in the form)?

## Related Potential ADRs
- [Thin Controllers with Stateless Domain Service Objects](../../consider/WEB/thin-controllers-with-stateless-domain-service-objects.md) (`WEB`)
- Dynamic Balance Derivation via In-Database SQL Aggregation (`AGG` / `DATA` — `ADR-001` in `HLD-001.md`)
- Strict Logical Multi-Tenancy and 404 Indistinguishability (`AUTH`)

## Additional Notes
- Because Sqr Finance is currently in the greenfield specification phase, this ADR serves as a prescriptive architectural blueprint for generating `app/controllers/*` and `app/views/*`.
