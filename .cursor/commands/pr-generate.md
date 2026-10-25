---
description: Gera o corpo e título de Pull Request no padrão estabelecido pelas PRs #1, #2 e #3 a partir do branch atual ou Task ID especificada
tags: [project, git, pr, github]
---

# Generate Pull Request Description (/pr-generate)

Este comando automatiza a geração de títulos e descrições completas de Pull Requests seguindo rigorosamente o padrão das PRs **#1**, **#2** e **#3** do projeto **sqr-finances**.

Ao ser invocado, o agente inspeciona o branch atual (ou a task informada), lê a especificação técnica correspondente em `docs/tech-specs/tasks/`, analisa o `git diff` e o histórico de commits, e preenche todas as seções do template sem nenhum placeholder pendente.

## Uso

```text
/pr-generate [task-id|branch] [--base=BRANCH] [--create] [--output=PATH]
```

### Exemplos

```bash
# Gera o PR para a task/branch atual do repositório
/pr-generate

# Gera o PR para uma task específica
/pr-generate T-004

# Gera o PR especificando a branch base
/pr-generate feat/T-004-session-auth-and-tenant-isolation --base=master

# Gera e abre a PR diretamente via GitHub CLI (gh)
/pr-generate T-004 --create
```

---

## Template das PRs #1, #2 e #3

O PR gerado DEVE seguir esta estrutura exata:

```markdown
## 📌 Identificação

- **Task:** `T-XXX`
- **Branch:** `<nome-da-branch>`
- **Base:** `<branch-base>`
- **Módulos Afetados:** `[MODULO_1]`, `[MODULO_2]`
- **Requisitos Atendidos:** `RF-XXX` (se houver, com descrição sucinta)
- **ADR Relacionada:** [ADR-XXX: Nome](caminho-relativo) (se houver)

---

## 🎯 Objetivo

<Parágrafo claro e detalhado contextualizando a necessidade técnica, o que foi implementado e conformidade com requisitos e ADRs.>

---

## 🛠️ O que foi feito?

### 1. <Grupo Lógico 1>
- <Item técnico detalhado>
- <Detalhes de configuração, models, migrations ou services>

### 2. <Grupo Lógico 2>
- <Item técnico detalhado>
- <Suíte de testes, linters, factories ou fixtures>

### 3. Governança e Arquitetura (ADR)
- Formalização da ADR (se aplicável);
- Atualização do índice consolidado de ADRs e checklist de tasks.

---

## 🧪 Como Testar?

1. Certifique-se de que os serviços no Docker estão operacionais:
   ```bash
   docker compose up -d
   docker compose ps
   ```
   *Ambos os serviços (`postgres` e `redis`) devem apresentar status `(healthy)`.*

2. Execute as migrations (se aplicável):
   ```bash
   bin/rails db:migrate
   ```

3. Execute a suíte de testes:
   ```bash
   bundle exec rspec <caminho_específico_se_houver> -fd
   ```
   *Esperado: X examples, 0 failures.*

4. Execute o linter de código:
   ```bash
   bundle exec rubocop
   ```
   *Esperado: X files inspected, no offenses detected.*

---

## ✅ Definition of Done (DoD)

- [x] <Item 1 do DoD da Tech Spec verificado>
- [x] <Item 2 do DoD da Tech Spec verificado>
- [x] <Comandos de teste passando>
- [x] `bundle exec rubocop` com 0 ofensas.
- [x] Formalizada a `docs/adrs/ADR-XXX-...` (se aplicável).

---

## 🔗 Referências

- [TS-TXXX: Especificação da Task](docs/tech-specs/tasks/TS-TXXX-nome.md)
- [PRD-001: MVP de Controle Financeiro](docs/prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
- [HLD-001: Arquitetura Monólito Modular e Hotwire](docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
- [ADR-XXX: Título da ADR](docs/adrs/ADR-XXX-nome.md)
```

---

## Instruções de Execução do Comando

Quando o usuário invocar `/pr-generate`:

### Passo 1: Descobrir Branch e Identificador da Task
1. Se o usuário passou um argumento (ex: `T-004` ou `feat/T-004-...`), utilize-o.
2. Caso contrário, execute `git branch --show-current` para obter o branch ativo.
3. Extraia o identificador `T-XXX` (ex: `T-001`, `T-002`, `T-003`, `T-004`).
4. Identifique o branch base:
   - Se `--base` foi informado, use o valor fornecido.
   - Caso contrário, verifique se a task possui dependência declarada em sua Tech Spec (`Dependência: T-00X`). Se a task predecessora ainda estiver em branch própria, use-a como base; caso contrário, use `master`.

### Passo 2: Ler a Especificação Técnica da Task
1. Localize o arquivo correspondente em `docs/tech-specs/tasks/TS-{TASK_ID}*.md`.
2. Extraia:
   - **Título e Módulos Afetados** (`[DATA]`, `[WEB]`, `[ASYNC]`, `[AUTH]`, etc.);
   - **Requisitos Atendidos** (`RF-XXX`);
   - **ADR Relacionada** (rascunho ou oficial);
   - **Objetivo Técnico**;
   - **Lista de Arquivos a Criar / Modificar**;
   - **Definition of Done (DoD)**;
   - **Referências documentais**.

### Passo 3: Analisar os Commits e o `git diff`
1. Execute `git log <base>..HEAD --oneline` para ver os commits da branch.
2. Execute `git diff --stat <base>..HEAD` para validar quais arquivos foram realmente alterados/criados.
3. Sintetize em tópicos claros e objetivos na seção **"🛠️ O que foi feito?"**:
   - Agrupe por responsabilidade (ex: Models/Migrations, Services, Controllers/Views, Configurações/Gems, Testes/RSpec, Governança/ADRs).
   - Destaque decisões de design relevantes mencionadas no código ou commits.

### Passo 4: Estruturar as Etapas de Teste
1. Adicione os comandos práticos para reprodução local:
   - Subida dos contêineres Docker (`docker compose up -d`);
   - Migrations ou seeds necessárias (`bin/rails db:migrate`);
   - Execução das specs específicas desenvolvidas na task (`bundle exec rspec spec/...`);
   - Execução do linter (`bundle exec rubocop`).
2. Indique os resultados esperados em itálico (*Esperado: X examples, 0 failures.*).

### Passo 5: Montar o Checklist do Definition of Done
1. Marque como `[x]` os itens cumpridos de acordo com o DoD da respectiva Tech Spec e a entrega real verificada no código.
2. Certifique-se de que RuboCop, testes e formalização de ADRs (se exigido) estão listados e validados.

### Passo 6: Gerar Links de Referências Relativas
1. Garanta que todos os links markdown na seção **"🔗 Referências"** apontem para caminhos relativos válidos existentes no projeto:
   - `docs/tech-specs/tasks/TS-TXXX-...`
   - `docs/prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md`
   - `docs/hlds/HLD-001-arquitetura-monolito-modular-hotwire.md`
   - `docs/adrs/ADR-XXX-...`

### Passo 7: Saída e Finalização
1. Formate o título do PR: `<type>(<task-id>): <Descrição>` (ex: `feat(T-004): Autenticação de Sessão e Isolamento Multi-tenant`).
2. Exiba o conteúdo formatado em Markdown pronto para cópia ou revisão.
3. Se o parâmetro `--output=<caminho>` for fornecido, salve o conteúdo no arquivo indicado.
4. Se a flag `--create` foi passada, execute o comando GitHub CLI:
   ```bash
   gh pr create --base "<base>" --head "<branch>" --title "<titulo>" --body "<corpo>"
   ```
