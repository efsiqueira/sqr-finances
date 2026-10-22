# TS-T010: Implementação do RecurrenceProcessorService e Sidekiq Workers de Recorrência

- **Task:** `T-010`
- **Branch:** `feat/T-010-recurrence-processor-and-workers`
- **Dependência:** `T-002, T-009`
- **Módulos Afetados:** `[REC]`, `[ASYNC]`
- **Requisitos Atendidos:** `RF-004` (Frequências Semanal, Mensal e Anual), `RF-005` (Geração Automática e Idempotente)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [fan-out-cron-scheduling-for-recurring-transactions.md](../../adrs/potential-adrs/consider/ASYNC/fan-out-cron-scheduling-for-recurring-transactions.md)
  - Destino Oficial: `docs/adrs/ADR-010-fan-out-cron-scheduling-for-recurring-transactions.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Implementar o orquestrador de ciclos `RecurrenceProcessorService` e os dois workers do Sidekiq (`RecurrenceSchedulerWorker` e `RecurrenceWorker`), além de registrar o agendamento diário (`00:05 UTC`) no `config/schedule.yml`.

---

## 2. Arquivos a Criar / Modificar

- `app/services/recurrence_processor_service.rb` (Novo)
- `app/workers/recurrence_scheduler_worker.rb` (Novo)
- `app/workers/recurrence_worker.rb` (Novo)
- `config/schedule.yml` (Registro do cron diário às `00:05 UTC`)
- `spec/services/recurrence_processor_service_spec.rb` (Novo)
- `spec/workers/recurrence_scheduler_worker_spec.rb` (Novo)
- `spec/workers/recurrence_worker_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/services/recurrence_processor_service.rb`

```ruby
class RecurrenceProcessorService
  def self.call(reference_date: Date.current)
    new(reference_date).call
  end

  def initialize(reference_date)
    @reference_date = reference_date.to_date
  end

  def call
    Recurrence.active.find_each do |recurrence|
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
    return [] if recurrence.start_date > @reference_date

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

### 3.2 `app/workers/recurrence_scheduler_worker.rb` e `app/workers/recurrence_worker.rb`

```ruby
# app/workers/recurrence_scheduler_worker.rb
class RecurrenceSchedulerWorker
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3

  def perform
    RecurrenceProcessorService.call(reference_date: Date.current)
  end
end
```

```ruby
# app/workers/recurrence_worker.rb
class RecurrenceWorker
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(recurrence_id, target_date_iso)
    recurrence = Recurrence.find_by(id: recurrence_id)
    return unless recurrence

    RecurrenceExecutionService.call(
      recurrence: recurrence,
      target_date: Date.iso8601(target_date_iso)
    )
  end
end
```

### 3.3 `config/schedule.yml`

```yaml
recurrence_scheduler:
  cron: "5 0 * * * UTC"
  class: "RecurrenceSchedulerWorker"
  queue: "default"
  description: "Varredura diária de regras de recorrência ativas e fan-out de ciclos elegíveis"
```

---

## 4. Plano de Testes (Isolado)

1. **`spec/services/recurrence_processor_service_spec.rb`**:
   - Calcula corretamente os ciclos pendentes para frequências `weekly`, `monthly` (incluindo fim de mês, ex.: 31/jan -> 28/fev) e `yearly`.
   - Enfileira um job `RecurrenceWorker` para cada ciclo elegível ainda não presente em `recurrence_executions` (catch-up retroativo).
   - Não enfileira ciclos já registrados em `recurrence_executions`.
   - Ignora recorrências pausadas (`active: false`) ou excluídas (`deleted_at.present?`).
   - Desativa automaticamente (`active: false`) a recorrência quando `end_date < reference_date` após enfileirar os ciclos devidos até `end_date`.
2. **`spec/workers/recurrence_scheduler_worker_spec.rb`** e **`spec/workers/recurrence_worker_spec.rb`**:
   - Valida a delegação correta para `RecurrenceProcessorService` e `RecurrenceExecutionService` (inclusive em modo `Sidekiq::Testing.inline!`).

---

## 5. Definition of Done (DoD)

- [ ] `RecurrenceProcessorService`, `RecurrenceSchedulerWorker` e `RecurrenceWorker` implementados.
- [ ] `config/schedule.yml` configurado com o cron diário `5 0 * * * UTC`.
- [ ] `bundle exec rspec spec/services/recurrence_processor_service_spec.rb spec/workers/` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-010-fan-out-cron-scheduling-for-recurring-transactions.md` a partir do rascunho em `potential-adrs/consider/ASYNC/`.
