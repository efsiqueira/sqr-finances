# TS-T006: Migration e Model de Recorrências (Recurrence) com Soft-Delete e Constraints Simétricas

- **Task:** `T-006`
- **Branch:** `feat/T-006-recurrence-model-and-soft-delete`
- **Dependência:** `T-003`
- **Módulos Afetados:** `[REC]`, `[DATA]`
- **Requisitos Atendidos:** `RF-004` (Regras de Recorrência), `RF-006` (Imutabilidade do Histórico e Exclusão Lógica)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [decoupled-generated-transactions-from-recurrence-rules.md](../../adrs/potential-adrs/must-document/REC/decoupled-generated-transactions-from-recurrence-rules.md)
  - Destino Oficial: `docs/adrs/ADR-002-decoupled-generated-transactions-and-history-preservation.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Criar a tabela `recurrences` no PostgreSQL 16 com suporte a *soft-delete* (`deleted_at`), índice parcial `idx_recurrences_user_active` e paridade completa de constraints `CHECK` em relação a `transactions`. Implementar o model `Recurrence` com gestão de ciclo de vida (`Ativa`, `Pausada`, `Excluída`) e método `soft_delete!`.

---

## 2. Arquivos a Criar / Modificar

- `db/migrate/YYYYMMDDHHMMSS_create_recurrences.rb` (Novo)
- `app/models/recurrence.rb` (Novo)
- `spec/factories/recurrences.rb` (Novo)
- `spec/models/recurrence_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 Migration (`CreateRecurrences`)

```ruby
class CreateRecurrences < ActiveRecord::Migration[8.0]
  def change
    create_table :recurrences do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, limit: 120, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :transaction_type, limit: 10, null: false
      t.string :payment_method, limit: 20
      t.string :frequency, limit: 15, null: false
      t.date :start_date, null: false
      t.date :end_date
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps null: false, default: -> { "NOW()" }
    end

    add_index :recurrences, [:user_id, :active],
              where: "deleted_at IS NULL",
              name: "idx_recurrences_user_active"

    add_check_constraint :recurrences, "amount > 0", name: "chk_rec_amount"
    add_check_constraint :recurrences, "transaction_type IN ('income', 'expense')", name: "chk_rec_transaction_type"
    add_check_constraint :recurrences, "frequency IN ('weekly', 'monthly', 'yearly')", name: "chk_rec_frequency"
    add_check_constraint :recurrences,
                         "(transaction_type = 'income' AND payment_method IS NULL) OR (transaction_type = 'expense' AND payment_method IN ('pix', 'debit', 'boleto', 'cash'))",
                         name: "chk_rec_payment_method"
    add_check_constraint :recurrences, "end_date IS NULL OR end_date >= start_date", name: "chk_rec_dates"
  end
end
```

### 3.2 Model (`app/models/recurrence.rb`)

```ruby
class Recurrence < ApplicationRecord
  TRANSACTION_TYPES = %w[income expense].freeze
  PAYMENT_METHODS   = %w[pix debit boleto cash].freeze
  FREQUENCIES       = %w[weekly monthly yearly].freeze

  belongs_to :user
  has_many :recurrence_executions, dependent: :restrict_with_exception

  normalizes :title, with: ->(title) { title.to_s.strip }
  normalizes :payment_method, with: ->(method) { method.presence }

  before_validation :clear_payment_method_for_income

  validates :title, presence: true, length: { maximum: 120 }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true, inclusion: { in: TRANSACTION_TYPES }
  validates :frequency, presence: true, inclusion: { in: FREQUENCIES }
  validates :start_date, presence: true
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }, if: :expense?
  validates :payment_method, absence: true, if: :income?
  validate  :end_date_after_or_equal_to_start_date

  scope :not_deleted, -> { where(deleted_at: nil) }
  scope :active, -> { not_deleted.where(active: true) }

  def income?
    transaction_type == "income"
  end

  def expense?
    transaction_type == "expense"
  end

  def deleted?
    deleted_at.present?
  end

  def soft_delete!
    update!(active: false, deleted_at: Time.current)
  end

  private

  def clear_payment_method_for_income
    self.payment_method = nil if income?
  end

  def end_date_after_or_equal_to_start_date
    return if end_date.blank? || start_date.blank?

    if end_date < start_date
      errors.add(:end_date, "deve ser maior ou igual à data de início")
    end
  end
end
```

### 3.3 Factory (`spec/factories/recurrences.rb`)

```ruby
FactoryBot.define do
  factory :recurrence do
    association :user
    title { "Aluguel" }
    amount { BigDecimal("2200.00") }
    transaction_type { "expense" }
    payment_method { "pix" }
    frequency { "monthly" }
    start_date { Date.current.beginning_of_month }
    end_date { nil }
    active { true }
    deleted_at { nil }

    trait :income do
      title { "Salário Recorrente" }
      transaction_type { "income" }
      payment_method { nil }
    end
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/models/recurrence_spec.rb`, validar:
1. Validações ActiveRecord de `title`, `amount > 0`, `transaction_type`, `frequency` (`weekly`, `monthly`, `yearly`), `start_date` e `end_date >= start_date`.
2. Validação condicional de `payment_method` para `expense` vs `income`.
3. Execução de `#soft_delete!`: define `active = false`, preenche `deleted_at` e remove o registro dos escopos `.not_deleted` e `.active` mantendo-o salvo no banco.
4. Violação das 5 constraints `CHECK` diretamente no PostgreSQL (`ActiveRecord::CheckViolation`).

---

## 5. Definition of Done (DoD)

- [ ] Migration de `recurrences` executada com `deleted_at`, índice parcial e 5 constraints `CHECK`.
- [ ] `bundle exec rspec spec/models/recurrence_spec.rb` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-002-decoupled-generated-transactions-and-history-preservation.md` a partir do rascunho em `potential-adrs/must-document/REC/`.
