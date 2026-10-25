## 📌 Identificação

- **Task:** `<!-- Ex: T-001 -->`
- **Branch:** `<!-- Ex: feat/T-003-user-model-and-migration -->`
- **Base:** `<!-- Ex: master ou chore/T-001-bootstrap-rails-docker-rspec -->`
- **Módulos Afetados:** `<!-- Ex: [AUTH], [DATA], [WEB], [ASYNC], Infraestrutura Local -->`
- **Requisitos Atendidos:** `<!-- Ex: RF-001 (Cadastro e Credenciais Únicas) - Opcional se aplicável -->`
- **ADR Relacionada:** `<!-- Ex: [ADR-007: Título](docs/adrs/ADR-007-...) - Opcional se aplicável -->`

---

## 🎯 Objetivo

<!-- Resumo claro e conciso do propósito das alterações, contextualizando o escopo e conformidade com requisitos e arquitetura. -->

---

## 🛠️ O que foi feito?

### 1. <!-- Nome do primeiro bloco de entrega -->
- <!-- Detalhe técnico da alteração -->
- <!-- Arquivos modificados/criados relevantes -->

### 2. <!-- Nome do segundo bloco de entrega -->
- <!-- Detalhe técnico da alteração -->

---

## 🧪 Como Testar?

1. Certifique-se de que os serviços no Docker estão operacionais:
   ```bash
   docker compose up -d
   docker compose ps
   ```
   *<!-- Status esperado dos serviços -->*

2. Prepare o banco de dados / execute migrations:
   ```bash
   bin/rails db:migrate
   ```

3. Execute a suíte de testes:
   ```bash
   bundle exec rspec <caminho_opcional_da_spec> -fd
   ```
   *<!-- Esperado: X examples, 0 failures -->*

4. Execute a verificação de código e linter:
   ```bash
   bundle exec rubocop
   ```
   *<!-- Esperado: X files inspected, no offenses detected -->*

---

## ✅ Definition of Done (DoD)

- [x] <!-- Item 1 do DoD da Tech Spec concluído -->
- [x] <!-- Item 2 do DoD da Tech Spec concluído -->
- [x] Testes automatizados executados e passando com 100% de sucesso.
- [x] RuboCop executado com 0 ofensas.
- [x] Documentação e ADRs atualizadas e formalizadas (se aplicável).

---

## 🔗 Referências

- [<!-- TS-TXXX: Título da Task -->](docs/tech-specs/tasks/<!-- TS-TXXX-arquivo.md -->)
- [<!-- PRD-XXX: Título do PRD -->](docs/prds/<!-- PRD-XXX-arquivo.md -->)
- [<!-- HLD-XXX: Título do HLD -->](docs/hlds/<!-- HLD-XXX-arquivo.md -->)
- [<!-- ADR-XXX: Título da ADR -->](docs/adrs/<!-- ADR-XXX-arquivo.md -->)
