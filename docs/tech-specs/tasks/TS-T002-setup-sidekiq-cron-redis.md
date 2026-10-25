# TS-T002: Configuração do Sidekiq 7, Sidekiq Cron e Redis Queue

- **Task:** `T-002`
- **Branch:** `chore/T-002-setup-sidekiq-cron-redis`
- **Dependência:** `T-001`
- **Módulos Afetados:** `[ASYNC]`
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [asynchronous-job-processing-with-redis-and-sidekiq.md](../../adrs/potential-adrs/must-document/ASYNC/asynchronous-job-processing-with-redis-and-sidekiq.md)
  - Destino Oficial: `docs/adrs/ADR-006-asynchronous-job-processing-with-redis-and-sidekiq.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [HLD-001: Arquitetura Monólito Modular e Hotwire](../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Configurar a infraestrutura de processamento em segundo plano com **Sidekiq 7** e **Sidekiq Cron** conectados ao **Redis 7**, preparando o ambiente para o agendamento diário e execução assíncrona de jobs sem depender das regras de recorrência (que serão implementadas na `T-010`).

---

## 2. Arquivos a Criar / Modificar

- `Gemfile` (Adição de `sidekiq` e `sidekiq-cron`)
- `config/initializers/sidekiq.rb` (Novo)
- `config/sidekiq.yml` (Novo)
- `config/schedule.yml` (Novo)
- `Procfile.dev` (Atualização para incluir o processo `worker: bundle exec sidekiq -C config/sidekiq.yml`)
- `spec/support/sidekiq.rb` (Novo — configuração de testes do Sidekiq)
- `spec/config/sidekiq_config_spec.rb` (Novo — spec de validação isolada)

---

## 3. Especificação de Implementação

### 3.1 Dependências no `Gemfile`

```ruby
gem "sidekiq", "~> 7.3"
gem "sidekiq-cron", "~> 1.12"
```

### 3.2 `config/initializers/sidekiq.rb`

```ruby
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  config.on(:startup) do
    schedule_file = Rails.root.join("config/schedule.yml")
    if File.exist?(schedule_file)
      schedule = YAML.load_file(schedule_file) || {}
      Sidekiq::Cron::Job.load_from_hash!(schedule) if schedule.any?
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
```

### 3.3 `config/sidekiq.yml`

```yaml
:concurrency: 5
:queues:
  - critical
  - default
  - low
```

### 3.4 `config/schedule.yml`

Inicialmente preparado (vazio ou com comentário estrutural até a `T-010` registrar o `RecurrenceSchedulerWorker`):

```yaml
# Jobs agendados pelo Sidekiq Cron (ex.: recurrence_scheduler na T-010)
{}
```

### 3.5 `spec/support/sidekiq.rb`

Incluir em `spec/rails_helper.rb`:

```ruby
require "sidekiq/testing"

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq::Worker.clear_all
  end
end
```

---

## 4. Plano de Testes (Isolado)

Criar `spec/config/sidekiq_config_spec.rb` para testar o enfileiramento de jobs e o carregamento do `schedule.yml` de forma totalmente independente de models de domínio:

```ruby
require "rails_helper"

RSpec.describe "Sidekiq & Sidekiq Cron Configuration" do
  let(:dummy_worker_class) do
    Class.new do
      include Sidekiq::Job
      sidekiq_options queue: :default, retry: 3

      def perform(payload)
        payload
      end
    end
  end

  before do
    stub_const("DummyDiagnosticsWorker", dummy_worker_class)
  end

  it "enqueues jobs into the default queue in fake testing mode" do
    Sidekiq::Testing.fake! do
      expect {
        DummyDiagnosticsWorker.perform_async("ping")
      }.to change(DummyDiagnosticsWorker.jobs, :size).by(1)
    end
  end

  it "loads config/schedule.yml cleanly without syntax errors" do
    schedule_path = Rails.root.join("config/schedule.yml")
    expect(File).to exist(schedule_path)
    expect { YAML.load_file(schedule_path) }.not_to raise_error
  end
end
```

---

## 5. Definition of Done (DoD)

- [x] `bundle install` instala `sidekiq` e `sidekiq-cron`.
- [x] `config/initializers/sidekiq.rb`, `config/sidekiq.yml` e `config/schedule.yml` criados.
- [x] `Procfile.dev` atualizado com o processo `worker`.
- [x] `bundle exec rspec spec/config/sidekiq_config_spec.rb` passa com sucesso.
- [x] Formalizar a `docs/adrs/ADR-006-asynchronous-job-processing-with-redis-and-sidekiq.md` a partir do rascunho em `potential-adrs/must-document/ASYNC/`.
