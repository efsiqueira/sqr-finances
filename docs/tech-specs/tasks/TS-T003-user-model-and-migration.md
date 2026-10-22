# TS-T003: Migration e Model de Usuário (User) com Credenciais Únicas e Bcrypt

- **Task:** `T-003`
- **Branch:** `feat/T-003-user-model-and-migration`
- **Dependência:** `T-001`
- **Módulos Afetados:** `[AUTH]`, `[DATA]`
- **Requisitos Atendidos:** `RF-001` (Cadastro e Credenciais Únicas)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [stateful-session-authentication-with-bcrypt.md](../../adrs/potential-adrs/must-document/AUTH/stateful-session-authentication-with-bcrypt.md)
  - Destino Oficial: `docs/adrs/ADR-007-stateful-session-authentication-with-bcrypt.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [PRD-001: MVP de Controle Financeiro](../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Criar a tabela `users` no PostgreSQL 16 (sem qualquer coluna de saldo estático, em conformidade com a `ADR-001`) e implementar o model `User` com criptografia `bcrypt` (`has_secure_password`), normalização de `email` e `username`, e método de busca por identificador duplo (`email` ou `username`).

---

## 2. Arquivos a Criar / Modificar

- `Gemfile` (Habilitar gem `bcrypt ~> 3.1.7`)
- `db/migrate/YYYYMMDDHHMMSS_create_users.rb` (Novo)
- `app/models/user.rb` (Novo)
- `spec/factories/users.rb` (Novo)
- `spec/models/user_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 Migration (`CreateUsers`)

```ruby
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name, limit: 150, null: false
      t.string :username, limit: 50, null: false
      t.string :email, limit: 255, null: false
      t.string :password_digest, limit: 255, null: false

      t.timestamps null: false, default: -> { "NOW()" }
    end

    add_index :users, :username, unique: true
    add_index :users, :email, unique: true
  end
end
```

### 3.2 Model (`app/models/user.rb`)

```ruby
class User < ApplicationRecord
  has_secure_password

  has_many :transactions, dependent: :destroy
  has_many :recurrences, dependent: :destroy

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :username, with: ->(username) { username.to_s.strip.downcase }
  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, length: { maximum: 150 }
  validates :username,
            presence: true,
            length: { minimum: 3, maximum: 50 },
            format: { with: /\A[a-z0-9_.]+\z/, message: "permite apenas letras, números, ponto e sublinhado" },
            uniqueness: { case_sensitive: false }
  validates :email,
            presence: true,
            length: { maximum: 255 },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || !password.nil? }

  def self.authenticate_by_login(login, password)
    normalized = login.to_s.strip.downcase
    return nil if normalized.blank? || password.blank?

    user = find_by("email = :login OR username = :login", login: normalized)
    user&.authenticate(password) || nil
  end
end
```

### 3.3 Factory (`spec/factories/users.rb`)

```ruby
FactoryBot.define do
  factory :user do
    name { "Ada Lovelace" }
    sequence(:username) { |n| "ada_lovelace_#{n}" }
    sequence(:email) { |n| "ada#{n}@sqrfinance.dev" }
    password { "SecretPass123!" }
    password_confirmation { "SecretPass123!" }
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/models/user_spec.rb`, validar:
1. Validações de presença e tamanho para `name`, `username`, `email` e `password` (mínimo 8 caracteres).
2. Normalização automática de `email` e `username` (`downcase` + `strip`).
3. Unicidade case-insensitive de `email` e `username` no ActiveRecord e via constraint `UNIQUE` no PostgreSQL.
4. Funcionamento de `.authenticate_by_login` informando `email`, informando `username`, ou falhando com senha incorreta.
5. Garantia de `ADR-001`: `expect(User.column_names).not_to include("balance", "current_balance")`.

---

## 5. Definition of Done (DoD)

- [ ] Migration executada e refletida em `db/schema.rb`.
- [ ] `bundle exec rspec spec/models/user_spec.rb` passa com 100% dos cenários verdes.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-007-stateful-session-authentication-with-bcrypt.md` a partir do rascunho em `potential-adrs/must-document/AUTH/`.
