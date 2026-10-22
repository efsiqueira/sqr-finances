# Diagramas de Arquitetura e Domínio - Sqr Finance

- **Documentos de Referência:**
  - [PRD-001: MVP de Controle Financeiro e Fluxo de Caixa Pessoal](../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
  - [HLD-001: Arquitetura Monólito Modular e Hotwire](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md)

## Visão Geral

Este documento consolida a modelagem técnica visual e arquitetural do Sqr Finance (MVP de Controle Financeiro e Fluxo de Caixa), fundamentado nas especificações do `PRD-001`, `HLD-001` e `TS-001`. O objetivo central é fornecer clareza estrutural para a engenharia de software sobre o modelo relacional de dados, o isolamento multi-tenant por conta de usuário, a derivação dinâmica e consistente do saldo financeiro e a automação assíncrona idempotente de movimentações periódicas com preservação integral de histórico.

## Elementos Identificados

- **User**: Entidade raiz para autenticação e isolamento lógico de dados (multi-tenancy). Contém identificadores únicos (`username` e `email`) e credenciais criptografadas via `bcrypt`. Não armazena saldo estático, sendo este derivado dinamicamente das transações.
- **Transaction**: Registro de fato contábil efetivo e independente ocorrido no fluxo de caixa. Contém título, tipo (`income` ou `expense`), valor monetário estritamente positivo (`NUMERIC(12,2)`), data de ocorrência (`occurred_at`) e forma de pagamento exclusiva para saídas (`pix`, `debit`, `boleto` ou `cash`). Não possui chave estrangeira direta para `Recurrence`.
- **Recurrence**: Regra de periodicidade configurada pelo usuário (`weekly`, `monthly` ou `yearly`) com início obrigatório e término opcional. Utiliza exclusão lógica (`deleted_at` e `active = false`) para preservar o histórico de auditoria quando removida.
- **RecurrenceExecution**: Entidade técnica de auditoria e linhagem que vincula `Recurrence` e `Transaction`, garantindo idempotência estrita no banco relacional através da constraint única composta `UNIQUE (recurrence_id, scheduled_for)`.
- **Rails MVC e Domain Services Unificados**: Estrutura orientada a Controllers enxutos (`Current.user`), Models ActiveRecord com validações espelhadas no PostgreSQL e três Services stateless dedicados:
  - `FinancialAggregationService`: Consolidação SQL pushdown de entradas, saídas, resultado líquido e saldo acumulado histórico.
  - `RecurrenceProcessorService`: Varredura de regras ativas, cálculo de ciclos devidos e encerramento de regras vencidas (`end_date`).
  - `RecurrenceExecutionService`: Materialização atômica de `Transaction` + `RecurrenceExecution` com tratamento de `ActiveRecord::RecordNotUnique`.
- **Interface Hotwire**: Camada de front-end reativa utilizando Turbo Frames para paginação e filtros sem recarregar a tela, Turbo Streams para mutações parciais no DOM e Stimulus JS para manipulação leve de eventos.
- **Agendador e Filas Assíncronas**: Componentes formados por Sidekiq Cron, Redis 7 e Workers dedicados (`RecurrenceSchedulerWorker` e `RecurrenceWorker`).

---

## Diagramas

### 1. Diagrama de Entidade-Relacionamento (ERD)

**Descrição**:
O Diagrama de Entidade-Relacionamento documenta o modelo relacional de dados do Sqr Finance implementado no PostgreSQL 16 em conformidade com o `HLD-001` e a `TS-001`. A entidade `USER` centraliza o isolamento de dados do sistema, associando-se às regras em `RECURRENCE` e aos lançamentos efetivos em `TRANSACTION`. Para garantir desacoplamento total e imutabilidade histórica (`ADR-002` e `ADR-004`), `TRANSACTION` não possui chave estrangeira para `RECURRENCE`; o rastreamento e a chave de idempotência `(recurrence_id, scheduled_for)` residem na tabela `RECURRENCE_EXECUTION`. A preservação do histórico é assegurada por `deleted_at` em `RECURRENCE`, `ON DELETE RESTRICT` em `recurrence_id` e `ON DELETE SET NULL` em `transaction_id`.

```mermaid
erDiagram
    USER ||--o{ RECURRENCE : "configura"
    USER ||--o{ TRANSACTION : "possui"
    RECURRENCE ||--o{ RECURRENCE_EXECUTION : "registra ciclo"
    TRANSACTION |o--o| RECURRENCE_EXECUTION : "originada em"

    USER {
        bigint id PK
        string name
        string username UK
        string email UK
        string password_digest
        timestamptz created_at
        timestamptz updated_at
    }

    TRANSACTION {
        bigint id PK
        bigint user_id FK
        string title
        numeric amount
        string transaction_type
        string payment_method
        timestamptz occurred_at
        timestamptz created_at
        timestamptz updated_at
    }

    RECURRENCE {
        bigint id PK
        bigint user_id FK
        string title
        numeric amount
        string transaction_type
        string payment_method
        string frequency
        date start_date
        date end_date
        boolean active
        timestamptz deleted_at
        timestamptz created_at
        timestamptz updated_at
    }

    RECURRENCE_EXECUTION {
        bigint id PK
        bigint recurrence_id FK
        bigint transaction_id FK
        date scheduled_for
        timestamptz created_at
    }
```

**Notas**:
- Índices únicos em `USER` nos campos `username` e `email` para assegurar identidade exclusiva.
- Índice composto `idx_transactions_user_date` em `TRANSACTION` nas colunas `(user_id, occurred_at DESC)` para otimizar agregações e ordenação cronológica.
- Índice parcial composto `idx_recurrences_user_active` em `RECURRENCE` nas colunas `(user_id, active) WHERE deleted_at IS NULL`.
- Constraint de unicidade composta `uq_recurrence_cycle` em `(recurrence_id, scheduled_for)` na tabela `RECURRENCE_EXECUTION` para garantia de idempotência na execução do Worker.
- Preservação de histórico: `RECURRENCE` utiliza *soft-delete* (`deleted_at`), `RECURRENCE_EXECUTION.recurrence_id` possui `ON DELETE RESTRICT` e `RECURRENCE_EXECUTION.transaction_id` é anulável com `ON DELETE SET NULL`.

---

### 2. Diagrama de Classes do Domínio

**Descrição**:
O Diagrama de Classes do Domínio detalha a modelagem orientada a objetos dos Models ActiveRecord e dos três Domain Services unificados da aplicação Ruby on Rails 8 (`FinancialAggregationService`, `RecurrenceProcessorService` e `RecurrenceExecutionService`).

```mermaid
classDiagram
    class User {
        +bigint id
        +string name
        +string username
        +string email
        +string password_digest
        +authenticate(password) boolean
        +transactions() ActiveRecord_Relation
        +recurrences() ActiveRecord_Relation
    }

    class Transaction {
        +bigint id
        +bigint user_id
        +string title
        +decimal amount
        +string transaction_type
        +string payment_method
        +datetime occurred_at
        +income?() boolean
        +expense?() boolean
    }

    class Recurrence {
        +bigint id
        +bigint user_id
        +string title
        +decimal amount
        +string transaction_type
        +string payment_method
        +string frequency
        +date start_date
        +date end_date
        +boolean active
        +datetime deleted_at
        +soft_delete!() void
    }

    class RecurrenceExecution {
        +bigint id
        +bigint recurrence_id
        +bigint transaction_id
        +date scheduled_for
        +datetime created_at
    }

    class FinancialAggregationService {
        +call(user, start_date, end_date)$ Result
    }

    class RecurrenceProcessorService {
        +call(reference_date)$ void
    }

    class RecurrenceExecutionService {
        +call(recurrence, target_date)$ Transaction
    }

    User "1" --> "*" Transaction : possui
    User "1" --> "*" Recurrence : configura
    Recurrence "1" --> "*" RecurrenceExecution : audita
    Transaction "0..1" <-- "0..1" RecurrenceExecution : referencia
    FinancialAggregationService ..> Transaction : agrega via SQL
    RecurrenceProcessorService ..> Recurrence : avalia ciclos
    RecurrenceProcessorService ..> RecurrenceExecutionService : despacha via Worker
    RecurrenceExecutionService ..> Transaction : materializa
    RecurrenceExecutionService ..> RecurrenceExecution : registra chave
```

**Notas**:
- Validação simétrica (`CHECK` + ActiveRecord) em `Transaction` e `Recurrence` exigindo `amount > 0`, `transaction_type` válido e `payment_method` exclusivo para `expense`.
- `FinancialAggregationService` retorna um Value Object imutável `Result` (`Data.define`) com os valores agregados em SQL.
- `RecurrenceExecutionService` isola a transação ACID de criação da `Transaction` e da `RecurrenceExecution`.

---

### 3. Diagrama de Arquitetura de Componentes

**Descrição**:
O Diagrama de Arquitetura de Componentes descreve a topologia em camadas da aplicação monolítica moderna construída com Ruby on Rails 8.

```mermaid
flowchart TD
    subgraph ClientLayer["Camada Cliente"]
        Browser["Navegador Web"]
        Turbo["Turbo Frames / Streams"]
        Stimulus["Stimulus Controllers"]
    end

    subgraph AppLayer["Aplicação Rails 8"]
        Router["Rails Router"]
        Controller["Thin Controllers"]
        Services["Domain Services"]
        Models["ActiveRecord Models"]
    end

    subgraph AsyncLayer["Processamento Assíncrono"]
        CronJob["Sidekiq Cron"]
        Queue["Redis 7 Queue"]
        Worker["Sidekiq Workers"]
    end

    subgraph DataLayer["Armazenamento"]
        Database[("PostgreSQL 16")]
    end

    Browser --> Turbo
    Browser --> Stimulus
    Turbo --> Router
    Stimulus --> Router
    Router --> Controller
    Controller --> Services
    Controller --> Models
    Services --> Models
    Models --> Database

    CronJob --> Queue
    Queue --> Worker
    Worker --> Services
```

---

### 4. Diagrama de Sequência: Registro de Transação e Atualização Reativa

**Descrição**:
Este diagrama de sequência documenta a interação ponta a ponta durante o cadastro de uma nova movimentação financeira efetiva (`RF-003`). O `TransactionsController` cria o registro diretamente através do escopo `Current.user.transactions`, aciona o `FinancialAggregationService` para recalcular os indicadores do período filtrado e retorna um payload `Turbo Stream` que atualiza o extrato, os cards de métricas e reseta o formulário em uma única viagem HTTP.

```mermaid
sequenceDiagram
    autonumber
    actor Usuario as Usuário
    participant Browser as Navegador Web
    participant Controller as TransactionsController
    participant Model as Transaction (ActiveRecord)
    participant Aggregator as FinancialAggregationService
    participant Database as PostgreSQL
    participant Turbo as Turbo Stream

    Usuario->>Browser: Submeter transação
    Browser->>Controller: POST /transactions
    Controller->>Model: Current.user.transactions.create(params)
    Model->>Database: INSERT INTO transactions
    Database-->>Model: Confirmação e ID
    Model-->>Controller: @transaction criada
    Controller->>Aggregator: call(user: Current.user, start_date:, end_date:)
    Aggregator->>Database: SUM entradas, saídas e saldo acumulado
    Database-->>Aggregator: Valores agregados
    Aggregator-->>Controller: Result DTO (@metrics)
    Controller-->>Turbo: Renderizar create.turbo_stream.erb
    Turbo-->>Browser: prepend row + replace metrics + update form
    Browser-->>Usuario: Exibir extrato e saldo atualizados
```

---

### 5. Diagrama de Fluxo: Processamento Idempotente de Recorrências

**Descrição**:
O Diagrama de Fluxo detalha a lógica combinada do `RecurrenceSchedulerWorker` (`RecurrenceProcessorService`) e do `RecurrenceWorker` (`RecurrenceExecutionService`) para materialização de movimentações recorrentes (`RF-005` e `RF-006`).

```mermaid
flowchart TD
    CronStart(["Sidekiq Cron (00:05 UTC)"])
    Scheduler["RecurrenceProcessorService"]
    FetchRec["Buscar Recorrências Ativas"]
    CalcDue["Calcular Ciclos Pendentes"]
    FanOut["Enfileirar RecurrenceWorker"]
    CheckEnd{"end_date < hoje?"}
    DeactRec["Desativar Regra (active = false)"]
    WorkerExec["RecurrenceExecutionService"]
    BeginTx["Iniciar Transação ACID"]
    CreateTx["Criar Transaction Independente"]
    CreateExec["Criar RecurrenceExecution"]
    UniqueCheck{"Violou uq_recurrence_cycle?"}
    RollbackDup["Rollback & Log Idempotente"]
    CommitTx(["Commit Transação"])

    CronStart --> Scheduler
    Scheduler --> FetchRec
    FetchRec --> CalcDue
    CalcDue --> FanOut
    FanOut --> CheckEnd
    CheckEnd -- Sim --> DeactRec
    CheckEnd -- Não --> WorkerExec
    DeactRec --> WorkerExec

    WorkerExec --> BeginTx
    BeginTx --> CreateTx
    CreateTx --> CreateExec
    CreateExec --> UniqueCheck
    UniqueCheck -- Sim --> RollbackDup
    UniqueCheck -- Não --> CommitTx
```

---

### 6. Diagrama de Sequência: Consulta e Agregação de Dashboard

**Descrição**:
Este diagrama de sequência ilustra o processo dinâmico de agregação e exibição das métricas financeiras ao navegar por períodos no dashboard (`RF-007` e `RF-008`) utilizando o `FinancialAggregationService`.

```mermaid
sequenceDiagram
    autonumber
    actor Usuario as Usuário
    participant Browser as Navegador Web
    participant Frame as Turbo Frame
    participant Controller as DashboardController
    participant Aggregator as FinancialAggregationService
    participant Database as PostgreSQL

    Usuario->>Browser: Selecionar filtro de período
    Browser->>Frame: Disparar requisição GET
    Frame->>Controller: GET /dashboard?period=month
    Controller->>Controller: Validar intervalo limite (<= 365 dias)
    Controller->>Aggregator: call(user: Current.user, start_date:, end_date:)
    Aggregator->>Database: SELECT SUM(income), SUM(expense) no período
    Database-->>Aggregator: Totais do período
    Aggregator->>Database: SELECT SUM(balance) histórico até end_date
    Database-->>Aggregator: Saldo acumulado histórico
    Aggregator->>Database: SELECT transactions do período ORDER BY occurred_at DESC
    Database-->>Aggregator: Lista ordenada
    Aggregator-->>Controller: FinancialAggregationService::Result
    Controller-->>Frame: Renderizar dashboard partials
    Frame-->>Browser: Atualizar Turbo Frames (metrics e list)
    Browser-->>Usuario: Visualizar métricas e extrato atualizados
```

---

### 7. Diagrama de Estados: Ciclo de Vida da Regra de Recorrência

**Descrição**:
O Diagrama de Estados descreve as fases e transições no ciclo de vida de uma regra de recorrência financeira (`RF-004` e `RF-006`). A transição para `Excluída` é implementada via *soft-delete* (`deleted_at = Time.current, active = false`), preservando permanentemente todas as transações passadas em `transactions` e todo o histórico de auditoria em `recurrence_executions`.

```mermaid
stateDiagram-v2
    [*] --> Ativa : Cadastrar regra (active = true)
    Ativa --> Pausada : Pausar regra (active = false)
    Pausada --> Ativa : Reativar regra (active = true)
    Ativa --> Concluída : end_date atingida (active = false)
    Ativa --> Excluída : Soft-delete (deleted_at preenchido, active = false)
    Pausada --> Excluída : Soft-delete (deleted_at preenchido, active = false)
    Concluída --> Excluída : Soft-delete (deleted_at preenchido, active = false)
    Excluída --> [*]
```
