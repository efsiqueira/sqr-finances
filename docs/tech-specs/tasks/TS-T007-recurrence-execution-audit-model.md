# TS-T007: Migration e Model de Execuções de Recorrência (RecurrenceExecution) com Chave de Idempotência

- **Task:** `T-007`
- **Branch:** `feat/T-007-recurrence-execution-audit-model`
- **Dependência:** `T-005, T-006`
- **Módulos Afetados:** `[REC]`, `[DATA]`
- **Requisitos Atendidos:** `RF-005` (Geração Idempotente de Recorrências), `RF-006` (Imutabilidade e Preservação de Histórico), `ADR-002`, `ADR-004`
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [database-enforced-idempotency-via-recurrence-execution.md](../../adrs/potential-adrs/must-document/REC/database-enforced-idempotency-via-recurrence-execution.md)
  - Destino Oficial: `docs/adrs/ADR-004-database-enforced-idempotency-via-recurrence-execution.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Criar a tabela técnica de auditoria e idempotência `recurrence_executions` no PostgreSQL 16 com a constraint única composta `uq_recurrence_cycle UNIQUE (recurrence_id, scheduled_for)`, bloqueio de exclusão física em `recurrence_id` (`ON DELETE RESTRICT`) e preservação de ciclo quando uma transação é excluída manualmente pelo usuário (`transaction_id` anulável com `ON DELETE SET NULL`).

---

## 2. Arquivos a Criar / Modificar

- `db/migrate/YYYYMMDDHHMMSS_create_recurrence_executions.rb` (Novo)
- `app/models/recurrence_execution.rb` (Novo)
- `spec/factories/recurrence_executions.rb` (Novo)
- `spec/models/recurrence_execution_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 Migration (`CreateRecurrenceExecutions`)

```ruby
class CreateRecurrenceExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :recurrence_executions do |t|
      t.references :recurrence, null: false, foreign_key: { on_delete: :restrict }
      t.references :transaction, null: true, foreign_key: { on_delete: :nullify }
      t.date :scheduled_for, null: false
      t.datetime :created_at, null: false, default: -> { "NOW()" }
    end

    add_index :recurrence_executions, [:recurrence_id, :scheduled_for],
              unique: true,
              name: "uq_recurrence_cycle"
  end
end
```

### 3.2 Model (`app/models/recurrence_execution.rb`)

```ruby
class RecurrenceExecution < ApplicationRecord
  belongs_to :recurrence
  belongs_to :financial_transaction,
             class_name: "Transaction",
             foreign_key: :transaction_id,
             optional: true

  validates :scheduled_for, presence: true, uniqueness: { scope: :recurrence_id }
end
```

> [!NOTE]
> Como `ActiveRecord::Base` possui um método de classe interno chamado `.transaction`, nomear a associação ActiveRecord como `financial_transaction` (ou acessar via `transaction_id`) evita colisões com `ActiveRecord::Transactions`, mantendo a coluna física `transaction_id` conforme o DDL da `TS-001`.

### 3.3 Factory (`spec/factories/recurrence_executions.rb`)

```ruby
FactoryBot.define do
  factory :recurrence_execution do
    association :recurrence
    financial_transaction { association :transaction, user: recurrence.user }
    scheduled_for { Date.current }
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/models/recurrence_execution_spec.rb`, validar:
1. Criação válida vinculando `Recurrence` e `Transaction` para uma data `scheduled_for`.
2. Tentativa de inserir um segundo registro com o mesmo par `(recurrence_id, scheduled_for)` (ignorando validação AR com `save(validate: false)`) dispara `ActiveRecord::RecordNotUnique` (`uq_recurrence_cycle`).
3. Excluir a `Transaction` vinculada (`transaction.destroy!`) mantém o registro `RecurrenceExecution` no banco com `transaction_id == nil` (`ON DELETE SET NULL`).
4. Tentativa de excluir fisicamente (`recurrence.delete` / `destroy`) uma `Recurrence` que possui execuções registradas é bloqueada pelo banco/ActiveRecord (`ON DELETE RESTRICT`).

---

## 5. Definition of Done (DoD)

- [ ] Migration de `recurrence_executions` executada com índice único `uq_recurrence_cycle`.
- [ ] `bundle exec rspec spec/models/recurrence_execution_spec.rb` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-004-database-enforced-idempotency-via-recurrence-execution.md` a partir do rascunho em `potential-adrs/must-document/REC/`.
