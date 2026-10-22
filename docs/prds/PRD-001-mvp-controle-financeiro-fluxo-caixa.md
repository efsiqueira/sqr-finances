# PRD-001: Sqr Finance - MVP de Controle Financeiro e Fluxo de Caixa Pessoal

- **ID:** PRD-001
- **Versão:** 1.2.0
- **Data:** 2026-10-21
- **Status:** Aprovado para Engenharia
- **Responsável:** Equipe de Produto e Engenharia Sqr Finance
- **Documentos Relacionados:**
  - [HLD-001: Arquitetura Monólito Modular e Hotwire](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../tech-specs/TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Problema e Proposta de Valor

Indivíduos têm dificuldade em manter clareza sobre seu fluxo de caixa mensal devido ao atrito de registro manual contínuo, esquecimento de contas periódicas e desconfiança sobre a exatidão do saldo apresentado por planilhas ou aplicativos complexos.

O **Sqr Finance** é uma aplicação web focada no registro descomplicado de movimentações financeiras efetivas, na automação confiável de receitas/despesas periódicas e na consolidação visual instantânea do fluxo de caixa por períodos selecionados.

---

## 2. Escopo

### 2.1 Incluso no MVP
- **Autenticação e Sessão:** Cadastro de usuário (e-mail e nome de usuário únicos), login seguro e isolamento estrito de dados por conta (*multi-tenancy* lógico).
- **Movimentações Efetivas:** Registro, edição, visualização e exclusão de receitas e despesas concretizadas.
- **Formas de Pagamento (apenas saídas):** Pix, débito, boleto e dinheiro (`payment_method` nulo para entradas).
- **Motor de Recorrências:** Regras de repetição (semanal, mensal, anual) com geração automática de transações independentes no histórico.
- **Filtros Temporais:** Navegação por dia, mês, ano ou intervalo personalizado (máximo de 12 meses / 365 dias).
- **Consolidação de Caixa:** Derivação contínua de:
  - Total de entradas no período.
  - Total de saídas no período.
  - Resultado líquido do período (Entradas − Saídas).
  - Saldo acumulado histórico total até a data filtrada.

### 2.2 Fora de Escopo (MVP)
- Cartão de crédito (gestão de faturas, limites e fechamento).
- Parcelamentos.
- Status de transação pendente/agendada avulsa (o sistema só registra fatos financeiros consolidados).
- Metodologias orçamentárias (50-30-20, base zero, envelopes).
- Categorias, tags customizadas e anexos de comprovantes.
- Integrações bancárias (Open Finance, OFX, conciliação automática).

---

## 3. Requisitos Funcionais

- **[RF-001] Cadastro e Autenticação:** Usuário cria conta informando nome, username, e-mail e senha. O login aceita e-mail ou username.
- **[RF-002] Isolamento de Dados:** Nenhuma operação permite que um usuário visualize, modifique ou deduza a existência de dados de outro usuário (resposta padrão para acessos não autorizados: *HTTP 404 Not Found*).
- **[RF-003] Gestão de Movimentações:** Cadastro com título, valor estritamente positivo (`amount > 0`), tipo (Entrada ou Saída), forma de pagamento (obrigatória para saídas e ausente para entradas) e data de ocorrência (`occurred_at`).
- **[RF-004] Regras de Recorrência:** Configuração de regras periódicas (semanal, mensal, anual) com data de início e término opcional.
- **[RF-005] Geração Idempotente de Recorrências:** O sistema gera automaticamente as movimentações devidas na data prevista. Falhas de execução ou retentativas nunca duplicam lançamentos para o mesmo ciclo.
- **[RF-006] Imutabilidade do Histórico e Auditoria:** Modificar ou excluir uma regra de recorrência afeta apenas ciclos futuros; movimentações passadas já geradas e o histórico de execuções (`recurrence_executions`) permanecem intactos via exclusão lógica (*soft-delete*) da regra.
- **[RF-007] Consulta e Filtros Temporais:** Listagem cronológica de movimentações com capacidade de filtrar por dia, mês, ano ou intervalo personalizado de até 365 dias.
- **[RF-008] Derivação Dinâmica de Saldos:** O saldo e os resultados do período são calculados exclusivamente a partir da agregação de fatos registrados, sem uso de campos estáticos de saldo na conta do usuário.

---

## 4. Critérios de Aceitação de Negócio

- [ ] Formulário de movimentações e recorrências recusa valores negativos ou iguais a zero.
- [ ] Taxa de duplicidade na geração de transações recorrentes é estritamente zero.
- [ ] Exclusão de uma regra de recorrência realiza desativação/exclusão lógica (`deleted_at`), preservando todas as transações passadas originadas por ela e a trilha de auditoria de execuções.
- [ ] Exclusão manual de uma transação gerada por recorrência não faz o motor recriá-la no ciclo já executado.
- [ ] O saldo consolidado em tela reflete deterministicamente o extrato de movimentações sem discrepâncias contábeis.
