# Sqr Finances

Aplicação web para controle financeiro pessoal e gestão de fluxo de caixa (MVP).

## Stack Tecnológica
- **Ruby:** 3.2+
- **Rails:** 8.0
- **Frontend / Reatividade:** Hotwire (Turbo & Stimulus) + Tailwind CSS
- **Banco de Dados:** PostgreSQL 16 (Authoritative ACID Datastore)
- **Mensageria / Cache:** Redis 7
- **Testes & Linter:** RSpec, FactoryBot, Shoulda Matchers e RuboCop

## Inicialização do Ambiente Local

### 1. Pré-requisitos
- Docker e Docker Compose
- Ruby 3.2+
- Bundler

### 2. Subir Serviços de Banco e Cache
```bash
docker compose up -d
```

### 3. Configurar Banco de Dados
```bash
bin/rails db:prepare
```

### 4. Executar a Suíte de Testes
```bash
bundle exec rspec
```

### 5. Executar Linter
```bash
bundle exec rubocop
```

### 6. Iniciar Servidor de Desenvolvimento
```bash
bin/dev
```
