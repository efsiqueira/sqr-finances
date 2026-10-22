# TS-001: Mecanismo de Movimentações, Recorrências e Agregação

- **ID:** TS-001
- **Versão:** 1.1.0
- **Data:** 2026-10-21
- **Stack:** Ruby 3.3+ | Rails 8.0 | PostgreSQL 16 | Sidekiq 7 | Hotwire
- **Responsável:** Engenharia de Software Sqr Finance
- **Documentos Relacionados:**
  - [PRD-001: MVP de Controle Financeiro e Fluxo de Caixa Pessoal](../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
  - [HLD-001: Arquitetura Monólito Modular e Hotwire](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
  - [Diagramas de Arquitetura e Domínio](../mermaid/sqr-finance-diagrams.md)

---

## 1. Schema do Banco de Dados (PostgreSQL DDL)

### 1.1 Decisões de Integridade e Preservação de Histórico no Schema
1. **Paridade de Constraints (`CHECK`) entre `transactions` e `recurrences`**: Ambas as tabelas validam no banco de dados `amount > 0`, `transaction_type IN ('income', 'expense')` e a regra condicional de `payment_method` (`IS NULL` quando `income`, e `IN ('pix', 'debit', 'boleto', 'cash')` quando `expense`). Além disso, `recurrences` valida `frequency IN ('weekly', 'monthly', 'yearly')`. Isso evita que uma recorrência malformada seja salva e só falhe em background durante a execução do worker.
2. **Preservação do Histórico (`recurrences` e `recurrence_executions`)**:
   - `recurrences` possui `deleted_at TIMESTAMP WITH TIME ZONE` para exclusão lógica (*soft-delete*). Quando o usuário exclui uma regra, o sistema define `active = FALSE` e `deleted_at = NOW()`.
   - `recurrence_executions.recurrence_id` utiliza `ON DELETE RESTRICT` para impedir a perda acidental do histórico de auditoria caso tentem remover fisicamente uma regra já executada.
   - `recurrence_executions.transaction_id` é anulável com `ON DELETE SET NULL`: se o usuário excluir manualmente do seu extrato uma transação que havia sido gerada por uma recorrência, o registro de execução do ciclo `(recurrence_id, scheduled_for)` permanece preservado no histórico, garantindo que o `RecurrenceWorker` não recrie a transação excluída.

```sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_digest VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE transactions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    transaction_type VARCHAR(10) NOT NULL, -- 'income', 'expense'
    payment_method VARCHAR(20),            -- NULL para 'income'; 'pix', 'debit', 'boleto', 'cash' para 'expense'
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_positive_amount CHECK (amount > 0),
    CONSTRAINT chk_transaction_type CHECK (transaction_type IN ('income', 'expense')),
    CONSTRAINT chk_payment_method CHECK (
        (transaction_type = 'income' AND payment_method IS NULL) OR 
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
    payment_method VARCHAR(20),            -- NULL para 'income'; 'pix', 'debit', 'boleto', 'cash' para 'expense'
    frequency VARCHAR(15) NOT NULL,        -- 'weekly', 'monthly', 'yearly'
    start_date DATE NOT NULL,
    end_date DATE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_rec_amount CHECK (amount > 0),
    CONSTRAINT chk_rec_transaction_type CHECK (transaction_type IN ('income', 'expense')),
    CONSTRAINT chk_rec_frequency CHECK (frequency IN ('weekly', 'monthly', 'yearly')),
    CONSTRAINT chk_rec_payment_method CHECK (
        (transaction_type = 'income' AND payment_method IS NULL) OR 
        (transaction_type = 'expense' AND payment_method IN ('pix', 'debit', 'boleto', 'cash'))
    ),
    CONSTRAINT chk_rec_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Índice composto para varredura de recorrências ativas e listagem por usuário
CREATE INDEX idx_recurrences_user_active ON recurrences (user_id, active) WHERE deleted_at IS NULL;

CREATE TABLE recurrence_executions (
    id BIGSERIAL PRIMARY KEY,
    recurrence_id BIGINT NOT NULL REFERENCES recurrences(id) ON DELETE RESTRICT,
    transaction_id BIGINT REFERENCES transactions(id) ON DELETE SET NULL,
    scheduled_for DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)
);
```

---

## 2. Design Unificado dos Domain Services

A camada de domínio é composta por exatamente **três Service Objects stateless**, todos expondo a interface de classe `.call(...)`:

1. **`FinancialAggregationService`**: Consolidação financeira e busca de transações do período.
2. **`RecurrenceProcessorService`**: Descoberta de ciclos devidos para recorrências ativas e atualização de ciclo de vida (`end_date`).
3. **`RecurrenceExecutionService`**: Execução atômica e idempotente de um ciclo individual `(recurrence, target_date)`.

### 2.1 `FinancialAggregationService`

Executa cálculos agregados diretamente no PostgreSQL, evitando instanciar coleções inteiras em memória.

```ruby
# app/services/financial_aggregation_service.rb
class FinancialAggregationService
  Result = Data.define(
    :total_income,
    :total_expense,
    :period_result,
    :accumulated_balance,
    :transactions
  )

  def self.call(user:, start_date:, end_date:)
    new(user, start_date, end_date).call
  end

  def initialize(user, start_date, end_date)
    @user = user
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
  end

  def call
    # 1. Totais consolidados do período selecionado
    period_aggregates = @user.transactions
      .where(occurred_at: @start_date..@end_date)
      .select(
        "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) AS income",
        "COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) AS expense"
      ).take

    income = period_aggregates.income.to_d
    expense = period_aggregates.expense.to_d
    result = income - expense

    # 2. Saldo acumulado histórico total até o fim do período
    accumulated_balance = @user.transactions
      .where("occurred_at <= ?", @end_date)
      .select(
        "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE -amount END), 0) AS balance"
      ).take.balance.to_d

    # 3. Transações do período ordenadas
    transactions = @user.transactions
      .where(occurred_at: @start_date..@end_date)
      .order(occurred_at: :desc)

    Result.new(
      total_income: income,
      total_expense: expense,
      period_result: result,
      accumulated_balance: accumulated_balance,
      transactions: transactions
    )
  end
end
```

### 2.2 `RecurrenceProcessorService`

Avalia as regras de recorrência ativas e não excluídas (`active: true, deleted_at: nil`), identifica todas as datas de ciclos devidos até a data de referência (`reference_date`) que ainda não constam em `recurrence_executions`, enfileira a execução de cada ciclo no `RecurrenceWorker` e desativa regras cuja `end_date` foi ultrapassada.

```ruby
# app/services/recurrence_processor_service.rb
class RecurrenceProcessorService
  def self.call(reference_date: Date.current)
    new(reference_date).call
  end

  def initialize(reference_date)
    @reference_date = reference_date
  end

  def call
    Recurrence.where(active: true, deleted_at: nil).find_each do |recurrence|
      due_dates_for(recurrence).each do |target_date|
        RecurrenceWorker.perform_async(recurrence.id, target_date.iso8601)
      end

      if recurrence.end_date.present? && recurrence.end_date < @reference_date
        recurrence.update!(active: false)
      end
    end
  end

  private

  def due_dates_for(recurrence)
    executed_dates = recurrence.recurrence_executions.pluck(:scheduled_for).to_set
    limit_date = [recurrence.end_date, @reference_date].compact.min

    dates = []
    step = 0
    loop do
      candidate = advance_date(recurrence.start_date, recurrence.frequency, step)
      break if candidate > limit_date

      dates << candidate unless executed_dates.include?(candidate)
      step += 1
    end
    dates
  end

  def advance_date(start_date, frequency, step)
    case frequency
    when "weekly"  then start_date + step.weeks
    when "monthly" then start_date + step.months
    when "yearly"  then start_date + step.years
    end
  end
end
```

### 2.3 `RecurrenceExecutionService`

Controla a criação atômica de uma ocorrência e trata violações de concorrência com idempotência silenciosa.

```ruby
# app/services/recurrence_execution_service.rb
class RecurrenceExecutionService
  def self.call(recurrence:, target_date:)
    new(recurrence, target_date).call
  end

  def initialize(recurrence, target_date)
    @recurrence = recurrence
    @target_date = target_date.is_a?(String) ? Date.iso8601(target_date) : target_date
  end

  def call
    return nil if @recurrence.deleted_at.present?

    ActiveRecord::Base.transaction do
      transaction = @recurrence.user.transactions.create!(
        title: @recurrence.title,
        amount: @recurrence.amount,
        transaction_type: @recurrence.transaction_type,
        payment_method: @recurrence.payment_method,
        occurred_at: @target_date.in_time_zone.middle_of_day
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

---

## 3. Contratos de Interface Hotwire

Os controllers respondem fragmentos HTML direcionados a Turbo Frames ou disparos de Turbo Stream.

### 3.1 Identificadores de Turbo Frames

- `turbo_frame_tag "dashboard_metrics"`: Cards com Saldo Acumulado, Total Entradas, Total Saídas e Resultado.
- `turbo_frame_tag "transactions_list"`: Tabela cronológica com as transações filtradas.
- `turbo_frame_tag "transaction_form_container"`: Modal/painel de inserção rápida.

### 3.2 Resposta Reativa (`POST /transactions`)

```erb
<%# app/views/transactions/create.turbo_stream.erb %>
<%= turbo_stream.prepend "transactions_table_body", partial: "transactions/row", locals: { transaction: @transaction } %>
<%= turbo_stream.replace "dashboard_metrics", partial: "dashboard/metrics", locals: { metrics: @metrics } %>
<%= turbo_stream.update "transaction_form_container", partial: "transactions/form", locals: { transaction: Transaction.new } %>
```

---

## 4. Background Workers (Sidekiq)

- **`RecurrenceSchedulerWorker`**: Roda diariamente via Sidekiq Cron (às `00:05 UTC`). Invoca `RecurrenceProcessorService.call` para varrer recorrências elegíveis e enfileirar jobs individuais por ciclo.
- **`RecurrenceWorker`**: Recebe `(recurrence_id, target_date)` e executa `RecurrenceExecutionService.call`.
