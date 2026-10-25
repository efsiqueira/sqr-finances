# Pull Request Template

Este template padroniza a abertura de Pull Requests no repositório **sqr-finances**, baseado nas diretrizes e convenções estabelecidas nas PRs fundamentais (#1, #2 e #3).

O arquivo de template oficial do GitHub encontra-se em [`.github/pull_request_template.md`](../../.github/pull_request_template.md).

Para preenchimento automatizado via comando no assistente de IA, utilize o comando:
```bash
/pr-generate [task-id|branch] [--create]
```
Consulte o arquivo de comando em [`.cursor/commands/pr-generate.md`](../../.cursor/commands/pr-generate.md) ou [`.claude/commands/pr-generate.md`](../../.claude/commands/pr-generate.md).

---

## Estrutura do Template

### 1. Título do Pull Request
O título segue o padrão de commits semânticos com o identificador da task:
```text
<type>(<task-id>): <Descrição sucinta e imperativa em pt-BR>
```
**Exemplos:**
- `chore(T-001): Bootstrap Rails 8, Docker Compose (PostgreSQL 16 + Redis 7) e Suíte RSpec`
- `chore(T-002): Setup Sidekiq 7, Sidekiq Cron e Redis Queue`
- `feat(T-003): Migration e Model User com Credenciais Únicas e Bcrypt`

---

### 2. Corpo do Pull Request

```markdown
## 📌 Identificação

- **Task:** `T-XXX`
- **Branch:** `tipo/T-XXX-nome-da-branch`
- **Base:** `master` (ou branch predecessora)
- **Módulos Afetados:** `[MODULO_1]`, `[MODULO_2]`
- **Requisitos Atendidos:** `RF-XXX` (se aplicável)
- **ADR Relacionada:** [ADR-XXX: Título](docs/adrs/ADR-XXX-slug.md) (se aplicável)

---

## 🎯 Objetivo

<Parágrafo explicando o contexto, propósito técnico e conformidade com requisitos/ADRs>

---

## 🛠️ O que foi feito?

### 1. <Grupo de mudanças 1>
- <Item técnico detalhado>
- <Arquivos tocados ou comportamentos ajustados>

### 2. <Grupo de mudanças 2>
- <Item técnico detalhado>

---

## 🧪 Como Testar?

1. Certifique-se de que os contêineres/serviços estão operacionais:
   ```bash
   docker compose up -d
   docker compose ps
   ```
   *Esperado: serviços postgres/redis saudáveis.*

2. Prepare as migrations / banco:
   ```bash
   bin/rails db:migrate
   ```

3. Execute os testes da task:
   ```bash
   bundle exec rspec <spec_path> -fd
   ```
   *Esperado: X examples, 0 failures.*

4. Execute o linter de código:
   ```bash
   bundle exec rubocop
   ```
   *Esperado: X files inspected, no offenses detected.*

---

## ✅ Definition of Done (DoD)

- [x] <Item 1 da Tech Spec cumprido>
- [x] <Item 2 da Tech Spec cumprido>
- [x] Suíte de testes automatizados executando com 0 falhas.
- [x] RuboCop com 0 ofensas detectadas.
- [x] Formalização de ADR e documentação associada atualizada (se aplicável).

---

## 🔗 Referências

- [TS-TXXX: Especificação da Task](docs/tech-specs/tasks/TS-TXXX-nome.md)
- [PRD-001: MVP de Controle Financeiro](docs/prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
- [HLD-001: Arquitetura Monólito Modular Hotwire](docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
- [ADR-XXX: Nome da ADR](docs/adrs/ADR-XXX-nome.md)
```
