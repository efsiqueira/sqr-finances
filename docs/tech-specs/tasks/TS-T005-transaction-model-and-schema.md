# TS-T005: Migration e Model de Movimentações (Transaction) com Constraints CHECK e Índice Temporal

- **Task:** `T-005`
- **Branch:** `feat/T-005-transaction-model-and-schema`
- **Dependência:** `T-003`
- **Módulos Afetados:** `[TXN]`, `[DATA]`
- **Requisitos Atendidos:** `RF-003` (Gestão de Movimentações Efetivas), `ADR-001` (Índice Composto Temporal), `ADR-002` (Fato Financeiro Independente)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunhos:
    - [decoupled-materialized-transaction-facts.md](../../adrs/potential-adrs/must-document/TXN/decoupled-materialized-transaction-facts.md)
    - [unsigned-monetary-model-with-dual-layer-invariants.md](../../adrs/potential-adrs/consider/TXN/unsigned-monetary-model-with-dual-layer-invariants.md)
  - Destino Oficial: `docs/adrs/ADR-009-materialized-transaction-facts-and-unsigned-monetary-model.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Criar a tabela `transactions` no PostgreSQL 16 fiel ao DDL da `TS-001` (incluindo precisão `NUMERIC(12, 2)`, constraints `CHECK` no banco de dados e o índice composto `idx_transactions_user_date (user_id, occurred_at DESC)`) e implementar o model `Transaction` com validações espelhadas e scopes temporais.

---

## 2. Arquivos a Criar / Modificar

- `db/migrate/YYYYMMDDHHMMSS_create_transactions.rb` (Novo)
- `app/models/transaction.rb` (Novo)
- `spec/factories/transactions.rb` (Novo)
- `spec/models/transaction_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 Migration (`CreateTransactions`)

```ruby
class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, limit: 120, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :transaction_type, limit: 10, null: false
      t.string :payment_method, limit: 20
      t.datetime :occurred_at, null: false

      t.timestamps null: false, default: -> { "NOW()" }
    end

    add_index :transactions, [:user_id, :occurred_at],
              order: { occurred_at: :desc },
              name: "idx_transactions_user_date"

    add_check_constraint :transactions, "amount > 0", name: "chk_positive_amount"
    add_check_constraint :transactions, "transaction_type IN ('income', 'expense')", name: "chk_transaction_type"
    add_check_constraint :transactions,
                         "(transaction_type = 'income' AND payment_method IS NULL) OR (transaction_type = 'expense' AND payment_method IN ('pix', 'debit', 'boleto', 'cash'))",
                         name: "chk_payment_method"
  end
end
```

### 3.2 Model (`app/models/transaction.rb`)

```ruby
class Transaction < ApplicationRecord
  TRANSACTION_TYPES = %w[income expense].freeze
  PAYMENT_METHODS   = %w[pix debit boleto cash].freeze

  belongs_to :user
  has_one :recurrence_execution, dependent: :nullify

  normalizes :title, with: ->(title) { title.to_s.strip }
  normalizes :payment_method, with: ->(method) { method.presence }

  before_validation :clear_payment_method_for_income

  validates :title, presence: true, length: { maximum: 120 }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true, inclusion: { in: TRANSACTION_TYPES }
  validates :occurred_at, presence: true
  validates :payment_method, presence: true, inclusion: { in: PAYMENT_METHODS }, if: :expense?
  validates :payment_method, absence: true, if: :income?

  scope :in_period, ->(start_date, end_date) { where(occurred_at: start_date.beginning_of_day..end_date.end_of_day) }
  scope :chronological, -> { order(occurred_at: :desc) }

  def income?
    transaction_type == "income"
  end

  def expense?
    transaction_type == "expense"
  end

  private

  def clear_payment_method_for_income
    self.payment_method = nil if income?
  end
end
```

### 3.3 Factory (`spec/factories/transactions.rb`)

```ruby
FactoryBot.define do
  factory :transaction do
    association :user
    title { "Salário Mensal" }
    amount { BigDecimal("5000.00") }
    transaction_type { "income" }
    payment_method { nil }
    occurred_at { Time.current }

    trait :income do
      transaction_type { "income" }
      payment_method { nil }
    end

    trait :expense do
      title { "Supermercado" }
      amount { BigDecimal("350.50") }
      transaction_type { "expense" }
      payment_method { "pix" }
    end
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/models/transaction_spec.rb`, validar:
1. Validações ActiveRecord para `title`, `amount > 0` (recusa `0` e negativos), `transaction_type` (`income`/`expense`) e `occurred_at`.
2. Validação condicional de `payment_method`: obrigatório e restrito a `pix`, `debit`, `boleto`, `cash` quando `expense`; limpo/nulo quando `income`.
3. Defesa em profundidade no PostgreSQL (usando `save(validate: false)` ou SQL bruto):
   - Inserir `amount <= 0` dispara `ActiveRecord::CheckViolation` (`chk_positive_amount`).
   - Inserir `expense` sem `payment_method` dispara `ActiveRecord::CheckViolation` (`chk_payment_method`).
4. Verificação da ausência de coluna `recurrence_id` na tabela `transactions` (`ADR-002`).

---

## 5. Definition of Done (DoD)

- [ ] Migration de `transactions` executada com índice composto e 3 `CHECK` constraints.
- [ ] `bundle exec rspec spec/models/transaction_spec.rb` passa integralmente.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-009-materialized-transaction-facts-and-unsigned-monetary-model.md` consolidando os rascunhos de `TXN`.
