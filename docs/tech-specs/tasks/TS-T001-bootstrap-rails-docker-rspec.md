# TS-T001: Bootstrap Rails 8, Docker Compose (PostgreSQL 16 + Redis 7) e Suíte RSpec

- **Task:** `T-001`
- **Branch:** `chore/T-001-bootstrap-rails-docker-rspec`
- **Dependência:** Nenhuma
- **Módulos Afetados:** `[DATA]`, `[WEB]`, Infraestrutura Local
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [postgresql-16-authoritative-acid-datastore-with-check-constraints-and-composite-indexing.md](../../adrs/potential-adrs/must-document/DATA/postgresql-16-authoritative-acid-datastore-with-check-constraints-and-composite-indexing.md)
  - Destino Oficial: `docs/adrs/ADR-005-postgresql-16-authoritative-acid-datastore.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [HLD-001: Arquitetura Monólito Modular e Hotwire](../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)

---

## 1. Objetivo Técnico

Inicializar a estrutura base do monólito **Ruby on Rails 8.0** configurado com **PostgreSQL 16**, **Tailwind CSS** e **Hotwire** (*Turbo* e *Stimulus*), provisionar os serviços locais de banco de dados e mensageria via `docker-compose.yml` (**PostgreSQL 16** + **Redis 7**) e configurar a suíte de testes automatizados (**RSpec**, **FactoryBot**, **Shoulda Matchers**) e linter (**RuboCop**).

---

## 2. Arquivos a Criar / Modificar

- `docker-compose.yml` (Novo)
- `.env.example` (Novo)
- `Gemfile` (Gerado pelo Rails + adição de gems de teste)
- `config/database.yml` (Configuração de conexão com o PostgreSQL do Docker)
- `config/application.rb` (Time zone `America/Sao_Paulo` ou `UTC` consistente e geradores RSpec)
- `.rspec` e `spec/spec_helper.rb` / `spec/rails_helper.rb` (Gerados pelo `rspec:install` + configuração de FactoryBot e Shoulda Matchers)
- `spec/requests/healthcheck_spec.rb` (Spec inicial para validar o bootstrap)

---

## 3. Especificação de Implementação

### 3.1 Comando de Geração do Rails 8

Gerar o esqueleto da aplicação preservando a pasta `docs/` existente (sem sobrescrever `README.md` caso desejado, e sem `solid_queue`/`solid_cache`/`solid_cable` caso o projeto utilize Redis + Sidekiq conforme `HLD-001`):

```bash
rails new . --database=postgresql --css=tailwind --skip-test --skip-jbuilder --force
```

### 3.2 `docker-compose.yml`

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: sqr_finances_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-sqr_finances}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-sqr_finances_secret}
      POSTGRES_DB: ${POSTGRES_DB:-sqr_finances_development}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-sqr_finances}"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: sqr_finances_redis
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  redis_data:
```

### 3.3 Dependências no `Gemfile` (Grupo `:development, :test`)

```ruby
group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
end

group :test do
  gem "shoulda-matchers", "~> 6.4"
  gem "capybara"
  gem "selenium-webdriver"
end
```

### 3.4 Configuração em `spec/rails_helper.rb`

```ruby
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

---

## 4. Plano de Testes (Isolado)

Criar `spec/requests/healthcheck_spec.rb` validando o endpoint nativo `/up` do Rails 8 e a conectividade ativa com o PostgreSQL 16:

```ruby
require "rails_helper"

RSpec.describe "Application Healthcheck", type: :request do
  describe "GET /up" do
    it "returns HTTP 200 OK when the application and database are healthy" do
      get rails_health_check_path
      expect(response).to have_http_status(:ok)
    end

    it "connects to PostgreSQL 16 successfully" do
      version = ActiveRecord::Base.connection.select_value("SHOW server_version;")
      expect(version).to start_with("16.")
    end
  end
end
```

---

## 5. Definition of Done (DoD)

- [ ] `docker compose up -d` sobe `postgres` e `redis` com status `healthy`.
- [ ] `bin/rails db:prepare` cria os bancos `sqr_finances_development` e `sqr_finances_test`.
- [ ] `bundle exec rspec` executa e passa sem erros.
- [ ] `bundle exec rubocop` executa com 0 ofensas.
- [ ] Formalizar a `docs/adrs/ADR-005-postgresql-16-authoritative-acid-datastore.md` a partir do rascunho em `potential-adrs/must-document/DATA/`.
