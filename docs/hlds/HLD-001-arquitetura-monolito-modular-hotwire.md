# HLD-001: Sqr Finance - Arquitetura Monólito Modular e Hotwire

- **ID:** HLD-001
- **Versão:** 1.2.0
- **Data:** 2026-10-21
- **Padrão Arquitetural:** Monólito Modular Web (Server-Driven UI)
- **Responsável:** Engenharia de Software Sqr Finance
- **Documentos Relacionados:**
  - [PRD-001: MVP de Controle Financeiro e Fluxo de Caixa Pessoal](../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md)
  - [Diagramas de Arquitetura e Domínio](../mermaid/sqr-finance-diagrams.md)

---

## 1. Visão Geral da Arquitetura

A solução adota uma topologia monolítica moderna baseada em **Ruby on Rails 8**, utilizando **PostgreSQL 16** como fonte primária e autoritativa de verdade (ACID) e **Redis 7 + Sidekiq 7** para processamento assíncrono em segundo plano.

A reatividade da interface é orientada pelo servidor através do ecossistema **Hotwire** (*Turbo Drive, Turbo Frames, Turbo Streams e Stimulus*), eliminando a complexidade de manter uma SPA desacoplada e a duplicação de contratos de API.

```text
                  ┌───────────────────────────────────────┐
                  │          Navegador Web (Hotwire)      │
                  └──────────────────┬────────────────────┘
                                     │ HTTPS (HTML / Turbo Stream)
                                     ▼
                  ┌───────────────────────────────────────┐
                  │       Rails 8 Application Server      │
                  │   (Controllers Magros + Current.user) │
                  └───────┬───────────────────────┬───────┘
                          │                       │
  Enfileiramento de Jobs  │                       │ Chamadas Síncronas
                          ▼                       ▼
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

---

## 2. Componentes e Responsabilidades Unificadas

Para manter os *Controllers* enxutos e garantir reuso entre fluxos síncronos (HTTP) e assíncronos (Sidekiq), as responsabilidades são estritamente divididas entre os seguintes componentes:

| Componente | Tipo | Responsabilidade Central |
|---|---|---|
| **Web Layer (Controllers & Hotwire)** | Síncrono | Autenticação, autorização de escopo (`Current.user`), CRUD direto de entidades simples via ActiveRecord (`Current.user.transactions`, `Current.user.recurrences`), validação de janela temporal (máx. 365 dias) e renderização de Turbo Streams/Frames. |
| **`FinancialAggregationService`** | Serviço de Domínio | Consolidação em nível de banco de dados (queries SQL pushdown otimizadas) de entradas do período, saídas do período, resultado líquido, saldo acumulado histórico e listagem ordenada de transações, retornando um DTO imutável (`Data.define`). |
| **`RecurrenceProcessorService`** | Serviço de Domínio | Avaliação de regras de recorrência ativas (`active = true` e `deleted_at IS NULL`), cálculo das datas de ciclos elegíveis pendentes (`scheduled_for`) até a data de referência e encerramento automático de regras que atingiram `end_date`. |
| **`RecurrenceExecutionService`** | Serviço de Domínio | Materialização atômica e idempotente de um único ciclo `(recurrence, target_date)` dentro de uma transação ACID: cria a `Transaction` independente e insere o registro em `RecurrenceExecution`, tratando `ActiveRecord::RecordNotUnique` silenciosamente. |
| **`RecurrenceSchedulerWorker` & `RecurrenceWorker`** | Assíncrono (Sidekiq) | Agendador diário via Sidekiq Cron (`00:05 UTC`) que aciona o `RecurrenceProcessorService` (fan-out) e workers consumidores que executam o `RecurrenceExecutionService` por ciclo. |
| **PostgreSQL 16** | Persistência | Garantia de integridade ACID, precisão `NUMERIC(12,2)`, constraints `CHECK` simétricas entre `transactions` e `recurrences`, e chaves únicas compostas para prevenção de concorrência. |

> [!NOTE]
> **Unificação de Nomenclatura de Services:** Nomes legados de rascunhos anteriores (`DashboardAggregatorService` e `TransactionService`) foram descontinuados. Toda consolidação financeira utiliza exclusivamente o `FinancialAggregationService`, e o CRUD padrão de transações opera diretamente sobre o escopo `Current.user.transactions` no `TransactionsController`, mantendo a arquitetura livre de camadas de pass-through desnecessárias.

---

## 3. Modelo Conceitual de Entidades

- **User:** Proprietário da conta e âncora de segurança (*tenant* lógico).
- **Transaction:** Fato financeiro materializado e independente. Possui tipo (`income`/`expense`), valor positivo, data de ocorrência (`occurred_at`) e forma de pagamento (exclusiva e obrigatória para `expense`). Não possui chave estrangeira direta para `Recurrence`.
- **Recurrence:** Regra programática de repetição periódica de transações. Utiliza exclusão lógica (`deleted_at` + `active = false`) para preservar o histórico de auditoria quando removida pelo usuário.
- **RecurrenceExecution:** Registro técnico de auditoria e linhagem que atua como chave de idempotência (`UNIQUE (recurrence_id, scheduled_for)`) entre uma `Recurrence` e a `Transaction` gerada.

```text
┌──────────────┐ 1       N ┌───────────────────────────┐
│     User     ├──────────►│        Transaction        │
└──────┬───────┘           └─────────────▲─────────────┘
       │ 1                               │ 0..1 (ON DELETE SET NULL)
       │                                 │
       │ N                               │ 0..1
┌──────▼───────┐ 1       N ┌─────────────┴─────────────┐
│  Recurrence  ├──────────►│    RecurrenceExecution    │
└──────────────┘ (RESTRICT)└───────────────────────────┘
```

---

## 4. Decisões Arquiteturais Fundamentais (ADRs)

- **ADR-001: Saldo Derivado Dinamicamente**  
  *Decisão:* Não armazenar saldo estático na tabela `users`.  
  *Motivação:* Elimina condições de corrida e inconsistências contábeis. A performance é garantida pelo `FinancialAggregationService` apoiado no índice composto `(user_id, occurred_at DESC)`.
- **ADR-002: Desacoplamento de Transações Geradas e Preservação de Histórico**  
  *Decisão:* Transações geradas por recorrência tornam-se entidades independentes na tabela `transactions` (sem coluna `recurrence_id`). Regras de recorrência excluídas sofrem *soft-delete* (`deleted_at` preenchido e `active = false`) com `ON DELETE RESTRICT` em `recurrence_executions.recurrence_id` e `ON DELETE SET NULL` em `recurrence_executions.transaction_id`.  
  *Motivação:* Fatos contábeis passados e a trilha de auditoria de execuções são imutáveis; alterações ou exclusões na regra afetam apenas registros futuros, e a exclusão manual de uma transação gerada pelo usuário não apaga o registro do ciclo já executado.
- **ADR-003: Arquitetura Orientada ao Servidor (Hotwire)**  
  *Decisão:* Utilizar Rails 8 com Hotwire sem SPA desacoplada.  
  *Motivação:* Reduz atrito cognitivo, simplifica a pilha tecnológica e entrega alta reatividade de interface.
- **ADR-004: Idempotência de Background via Banco Relacional**  
  *Decisão:* Garantir idempotência de jobs assíncronos através de constraint única composta em `(recurrence_id, scheduled_for)` na tabela `recurrence_executions`.  
  *Motivação:* Previne duplicação de transações mesmo sob retries de rede ou concorrência de workers.
