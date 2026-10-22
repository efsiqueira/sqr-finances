# TS-T011: Dashboard e Filtros Temporais com Turbo Frames (RF-007, RF-008)

- **Task:** `T-011`
- **Branch:** `feat/T-011-dashboard-temporal-filters-hotwire`
- **Dependência:** `T-004, T-008`
- **Módulos Afetados:** `[WEB]`, `[AGG]`
- **Requisitos Atendidos:** `RF-007` (Consulta e Filtros Temporais até 365 dias), `RF-008` (Consolidação Dinâmica em Tela), `ADR-003` (Hotwire Turbo Frames)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [server-driven-reactive-ui-with-rails-8-and-hotwire.md](../../adrs/potential-adrs/must-document/WEB/server-driven-reactive-ui-with-rails-8-and-hotwire.md)
  - Destino Oficial: `docs/adrs/ADR-003-server-driven-reactive-ui-with-rails-8-and-hotwire.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Implementar o `DashboardController` e as views Hotwire com os 3 Turbo Frames canônicos (`dashboard_metrics`, `transactions_list` e `transaction_form_container`), suportando navegação temporal por **dia**, **mês**, **ano** ou **intervalo personalizado** (limitado a no máximo 365 dias).

---

## 2. Arquivos a Criar / Modificar

- `app/controllers/concerns/period_filterable.rb` (Novo — resolução de `[start_date, end_date]` compartilhável com `TransactionsController`)
- `app/controllers/dashboard_controller.rb` (Novo)
- `app/views/dashboard/index.html.erb` (Novo)
- `app/views/dashboard/_metrics.html.erb` (Novo)
- `app/views/transactions/_list.html.erb` e `app/views/transactions/_row.html.erb` (Novos)
- `config/routes.rb` (`root "dashboard#index"` e `get "dashboard", to: "dashboard#index"`)
- `spec/requests/dashboard_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/controllers/concerns/period_filterable.rb`

Extrai e valida o filtro de período da requisição ou sessão, garantindo a regra de negócio de no máximo 365 dias (`RF-007`):

```ruby
module PeriodFilterable
  extend ActiveSupport::Concern

  MAX_CUSTOM_DAYS = 365

  private

  def resolve_period_range
    period = params[:period].presence || session[:dashboard_period] || "month"
    ref_date = parse_date(params[:date]) || Date.current

    start_date, end_date = case period
    when "day"
      [ref_date, ref_date]
    when "year"
      [ref_date.beginning_of_year, ref_date.end_of_year]
    when "custom"
      resolve_custom_range(ref_date)
    else
      period = "month"
      [ref_date.beginning_of_month, ref_date.end_of_month]
    end

    session[:dashboard_period] = period
    session[:dashboard_start_date] = start_date.iso8601
    session[:dashboard_end_date] = end_date.iso8601

    [start_date, end_date, period]
  end

  def resolve_custom_range(fallback_date)
    custom_start = parse_date(params[:start_date]) || parse_date(session[:dashboard_start_date]) || fallback_date.beginning_of_month
    custom_end   = parse_date(params[:end_date])   || parse_date(session[:dashboard_end_date])   || fallback_date.end_of_month

    if custom_end < custom_start
      @filter_error = "A data final deve ser maior ou igual à data inicial."
      return [fallback_date.beginning_of_month, fallback_date.end_of_month]
    end

    if (custom_end - custom_start).to_i > MAX_CUSTOM_DAYS
      @filter_error = "O intervalo personalizado não pode exceder 365 dias."
      custom_end = custom_start + MAX_CUSTOM_DAYS.days
    end

    [custom_start, custom_end]
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
```

### 3.2 `app/controllers/dashboard_controller.rb`

```ruby
class DashboardController < ApplicationController
  include PeriodFilterable

  def index
    @start_date, @end_date, @period = resolve_period_range
    @metrics = FinancialAggregationService.call(
      user: Current.user,
      start_date: @start_date,
      end_date: @end_date
    )
  end
end
```

### 3.3 Contratos de Turbo Frames em `app/views/dashboard/index.html.erb`

A view deve conter obrigatoriamente os identificadores definidos na `TS-001`:
- `<%= turbo_frame_tag "dashboard_metrics" do %>` renderizando `dashboard/metrics` (Total Entradas, Total Saídas, Resultado do Período e Saldo Acumulado).
- `<%= turbo_frame_tag "transaction_form_container" do %>` (container para o formulário de nova transação).
- `<%= turbo_frame_tag "transactions_list" do %>` contendo `<tbody id="transactions_table_body">` com as linhas `transactions/row`.

---

## 4. Plano de Testes (Isolado)

Em `spec/requests/dashboard_spec.rb`, validar:
1. Redireciona para `/login` quando não autenticado.
2. Exibe os 4 cards consolidados (`total_income`, `total_expense`, `period_result`, `accumulated_balance`) e as transações do mês atual por padrão (`period=month`).
3. Filtra corretamente por `period=day`, `period=month`, `period=year` e `period=custom` (`start_date` e `end_date`).
4. Aplica o limite de 365 dias quando `end_date - start_date > 365`, exibindo mensagem de aviso sem quebrar a página.
5. Presença dos `turbo-frame` com IDs `dashboard_metrics`, `transactions_list` e `transaction_form_container` no HTML retornado.

---

## 5. Definition of Done (DoD)

- [ ] `DashboardController`, `PeriodFilterable` e views com Turbo Frames implementados.
- [ ] `bundle exec rspec spec/requests/dashboard_spec.rb` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-003-server-driven-reactive-ui-with-rails-8-and-hotwire.md` a partir do rascunho em `potential-adrs/must-document/WEB/`.
