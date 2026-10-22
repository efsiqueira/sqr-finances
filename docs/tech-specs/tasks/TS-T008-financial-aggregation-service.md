# TS-T008: Implementação do FinancialAggregationService (Consolidação SQL Pushdown)

- **Task:** `T-008`
- **Branch:** `feat/T-008-financial-aggregation-service`
- **Dependência:** `T-005`
- **Módulos Afetados:** `[AGG]`, `[DATA]`
- **Requisitos Atendidos:** `RF-007` (Filtros Temporais e Ordenação), `RF-008` (Derivação Dinâmica de Saldos), `ADR-001`
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunhos:
    - [dynamic-balance-derivation-without-static-balance-state.md](../../adrs/potential-adrs/must-document/AGG/dynamic-balance-derivation-without-static-balance-state.md)
    - [in-database-sql-pushdown-aggregation-with-bounded-temporal-window.md](../../adrs/potential-adrs/consider/AGG/in-database-sql-pushdown-aggregation-with-bounded-temporal-window.md)
  - Destino Oficial: `docs/adrs/ADR-001-dynamic-balance-derivation-and-sql-pushdown.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Implementar o serviço de domínio stateless `FinancialAggregationService` que calcula diretamente no PostgreSQL (via `SUM(CASE WHEN ...)`) o total de entradas do período, o total de saídas do período, o resultado líquido do período, o saldo acumulado histórico até `end_date` e a relação ordenada de transações do período, encapsulando o retorno no Value Object imutável `FinancialAggregationService::Result` (`Data.define`).

---

## 2. Arquivos a Criar / Modificar

- `app/services/financial_aggregation_service.rb` (Novo)
- `spec/services/financial_aggregation_service_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/services/financial_aggregation_service.rb`

```ruby
class FinancialAggregationService
  Result = Data.define(
    :total_income,
    :total_expense,
    :period_result,
    :accumulated_balance,
    :transactions
  )

  def self.call(user:, start_date:, end_date:)
    new(user, start_date, end_date).call
  end

  def initialize(user, start_date, end_date)
    @user = user
    @start_date = start_date.beginning_of_day
    @end_date = end_date.end_of_day
  end

  def call
    period_aggregates = @user.transactions
      .where(occurred_at: @start_date..@end_date)
      .select(
        "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) AS income",
        "COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) AS expense"
      ).take

    income = period_aggregates.income.to_d
    expense = period_aggregates.expense.to_d
    result = income - expense

    accumulated_balance = @user.transactions
      .where("occurred_at <= ?", @end_date)
      .select(
        "COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE -amount END), 0) AS balance"
      ).take.balance.to_d

    transactions = @user.transactions
      .where(occurred_at: @start_date..@end_date)
      .order(occurred_at: :desc)

    Result.new(
      total_income: income,
      total_expense: expense,
      period_result: result,
      accumulated_balance: accumulated_balance,
      transactions: transactions
    )
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/services/financial_aggregation_service_spec.rb`, validar:
1. **Período vazio (sem transações)**: retorna `BigDecimal("0.0")` para `total_income`, `total_expense`, `period_result` e `accumulated_balance`, e lista `transactions` vazia.
2. **Consolidação exata do período**: dado um usuário com receitas (`5000.00`, `250.75`) e despesas (`1200.50`, `99.25`) dentro de `[start_date, end_date]`, calcula `total_income = 5250.75`, `total_expense = 1300.00`, `period_result = 3950.75`.
3. **Saldo acumulado histórico (`accumulated_balance`)**:
   - Inclui transações anteriores a `start_date` (`occurred_at < start_date`) e dentro do período (`occurred_at <= end_date`).
   - Ignora transações posteriores a `end_date` (`occurred_at > end_date`).
4. **Isolamento Multi-Tenant (`RF-002`)**: transações pertencentes a `other_user` no mesmo período jamais afetam os totais ou a listagem de `user`.
5. **Imutabilidade do DTO**: verifica que o retorno é instância de `FinancialAggregationService::Result` (`frozen? == true`) e os valores monetários são instâncias de `BigDecimal`.

---

## 5. Definition of Done (DoD)

- [ ] `app/services/financial_aggregation_service.rb` implementado.
- [ ] `bundle exec rspec spec/services/financial_aggregation_service_spec.rb` passa com 100% dos cenários.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-001-dynamic-balance-derivation-and-sql-pushdown.md` consolidando os rascunhos de `AGG`.
