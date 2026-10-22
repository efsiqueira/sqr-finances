# TS-T009: Implementação do RecurrenceExecutionService (Materialização Atômica e Idempotente)

- **Task:** `T-009`
- **Branch:** `feat/T-009-recurrence-execution-service`
- **Dependência:** `T-007`
- **Módulos Afetados:** `[REC]`, `[TXN]`, `[DATA]`
- **Requisitos Atendidos:** `RF-005` (Geração Idempotente de Recorrências — Taxa Zero de Duplicidade), `RF-006` (Imutabilidade do Histórico), `ADR-002`, `ADR-004`
- **ADR Relacionada (Atualizar no DoD):**
  - Destinos Oficiais: `docs/adrs/ADR-004-database-enforced-idempotency-via-recurrence-execution.md` e `docs/adrs/ADR-002-decoupled-generated-transactions-and-history-preservation.md` (vincular evidência de `app/services/recurrence_execution_service.rb`)
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Implementar o serviço `RecurrenceExecutionService` responsável por materializar de forma atômica uma `Transaction` independente e registrar sua execução na tabela `recurrence_executions` para uma data de ciclo (`target_date`), garantindo taxa zero de duplicidade por meio do tratamento de `ActiveRecord::RecordNotUnique`.

---

## 2. Arquivos a Criar / Modificar

- `app/services/recurrence_execution_service.rb` (Novo)
- `spec/services/recurrence_execution_service_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/services/recurrence_execution_service.rb`

```ruby
class RecurrenceExecutionService
  def self.call(recurrence:, target_date:)
    new(recurrence, target_date).call
  end

  def initialize(recurrence, target_date)
    @recurrence = recurrence
    @target_date = target_date.is_a?(String) ? Date.iso8601(target_date) : target_date.to_date
  end

  def call
    return nil if @recurrence.deleted? || !@recurrence.active?

    transaction = nil

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
        financial_transaction: transaction,
        scheduled_for: @target_date
      )
    end

    transaction
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("Recurrence ##{@recurrence.id} for #{@target_date} already executed.")
    nil
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/services/recurrence_execution_service_spec.rb`, validar:
1. **Materialização com sucesso**: cria 1 `Transaction` com os atributos copiados da `Recurrence` e `occurred_at` no meio do dia de `target_date`, além de 1 `RecurrenceExecution` vinculando ambos com `scheduled_for == target_date`.
2. **Idempotência estrita (`RF-005`)**: chamar `RecurrenceExecutionService.call(recurrence:, target_date:)` duas vezes seguidas para a mesma data cria apenas 1 `Transaction` e 1 `RecurrenceExecution`; a segunda chamada retorna `nil` sem levantar exceção.
3. **Preservação após exclusão manual da transação**: se a `Transaction` gerada for excluída pelo usuário (`transaction.destroy!`), uma nova chamada ao `RecurrenceExecutionService` para a mesma `target_date` **não** recria a transação (pois o registro em `recurrence_executions` continua existindo).
4. **Imutabilidade do histórico (`RF-006`)**: alterar `title` ou `amount` da `Recurrence` ou executar `recurrence.soft_delete!` após a geração não altera a `Transaction` já materializada.
5. **Guarda de estado**: se a recorrência estiver pausada (`active: false`) ou excluída (`deleted_at.present?`), retorna `nil` sem criar registros.

---

## 5. Definition of Done (DoD)

- [ ] `app/services/recurrence_execution_service.rb` implementado.
- [ ] `bundle exec rspec spec/services/recurrence_execution_service_spec.rb` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Atualizar `ADR-002` e `ADR-004` em `docs/adrs/` referenciando `app/services/recurrence_execution_service.rb`.
