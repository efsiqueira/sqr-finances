# TS-T012: CRUD Reativo de Movimentações com Turbo Streams e Stimulus (RF-002, RF-003)

- **Task:** `T-012`
- **Branch:** `feat/T-012-reactive-transactions-crud-hotwire`
- **Dependência:** `T-011`
- **Módulos Afetados:** `[WEB]`, `[TXN]`, `[AGG]`
- **Requisitos Atendidos:** `RF-002` (Isolamento de Dados com `404 Not Found`), `RF-003` (Gestão de Movimentações), `ADR-003` (Hotwire Turbo Streams)
- **ADR Relacionada (Atualizar no DoD):**
  - Destino Oficial: `docs/adrs/ADR-003-server-driven-reactive-ui-with-rails-8-and-hotwire.md` (vincular os templates Turbo Stream e o Stimulus controller implementados)
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Implementar o CRUD completo de movimentações financeiras efetivas no `TransactionsController` operando estritamente sobre `Current.user.transactions`, com respostas reativas via **Turbo Streams** (que atualizam simultaneamente a tabela de extrato, os cards de saldo do `dashboard_metrics` e o container do formulário) e um controller **Stimulus** para alternar a visibilidade/obrigatoriedade do campo `payment_method` entre entradas e saídas.

---

## 2. Arquivos a Criar / Modificar

- `app/controllers/transactions_controller.rb` (Novo)
- `app/views/transactions/_form.html.erb` (Novo)
- `app/views/transactions/edit.html.erb` (Novo — dentro de Turbo Frame)
- `app/views/transactions/create.turbo_stream.erb` (Novo)
- `app/views/transactions/update.turbo_stream.erb` (Novo)
- `app/views/transactions/destroy.turbo_stream.erb` (Novo)
- `app/javascript/controllers/transaction_type_controller.js` (Novo — Stimulus)
- `config/routes.rb` (`resources :transactions, only: %i[new create edit update destroy]`)
- `spec/requests/transactions_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/controllers/transactions_controller.rb`

```ruby
class TransactionsController < ApplicationController
  include PeriodFilterable

  before_action :set_transaction, only: %i[edit update destroy]

  def new
    @transaction = Current.user.transactions.new(occurred_at: Time.current, transaction_type: "expense")
  end

  def create
    @transaction = Current.user.transactions.new(transaction_params)

    if @transaction.save
      load_dashboard_metrics
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to root_path, notice: "Movimentação registrada." }
      end
    else
      render partial: "transactions/form", locals: { transaction: @transaction }, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @transaction.update(transaction_params)
      load_dashboard_metrics
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to root_path, notice: "Movimentação atualizada." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.destroy!
    load_dashboard_metrics

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path, status: :see_other, notice: "Movimentação excluída." }
    end
  end

  private

  def set_transaction
    @transaction = Current.user.transactions.find(params[:id])
  end

  def load_dashboard_metrics
    start_date, end_date, = resolve_period_range
    @metrics = FinancialAggregationService.call(
      user: Current.user,
      start_date: start_date,
      end_date: end_date
    )
  end

  def transaction_params
    params.require(:transaction).permit(:title, :amount, :transaction_type, :payment_method, :occurred_at)
  end
end
```

### 3.2 Templates Turbo Stream

```erb
<%# app/views/transactions/create.turbo_stream.erb %>
<%= turbo_stream.prepend "transactions_table_body", partial: "transactions/row", locals: { transaction: @transaction } %>
<%= turbo_stream.replace "dashboard_metrics", partial: "dashboard/metrics", locals: { metrics: @metrics } %>
<%= turbo_stream.update "transaction_form_container", partial: "transactions/form", locals: { transaction: Current.user.transactions.new(occurred_at: Time.current, transaction_type: "expense") } %>
```

```erb
<%# app/views/transactions/update.turbo_stream.erb %>
<%= turbo_stream.replace dom_id(@transaction), partial: "transactions/row", locals: { transaction: @transaction } %>
<%= turbo_stream.replace "dashboard_metrics", partial: "dashboard/metrics", locals: { metrics: @metrics } %>
```

```erb
<%# app/views/transactions/destroy.turbo_stream.erb %>
<%= turbo_stream.remove dom_id(@transaction) %>
<%= turbo_stream.replace "dashboard_metrics", partial: "dashboard/metrics", locals: { metrics: @metrics } %>
```

### 3.3 Stimulus Controller (`app/javascript/controllers/transaction_type_controller.js`)

Oculta e desabilita o seletor de `payment_method` quando o usuário seleciona `income`, e exibe/habilita quando seleciona `expense`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["typeSelect", "paymentMethodWrapper", "paymentMethodInput"]

  connect() {
    this.toggle()
  }

  toggle() {
    const isExpense = this.typeSelectTarget.value === "expense"
    this.paymentMethodWrapperTarget.classList.toggle("hidden", !isExpense)
    this.paymentMethodInputTarget.disabled = !isExpense
    if (!isExpense) {
      this.paymentMethodInputTarget.value = ""
    }
  }
}
```

---

## 4. Plano de Testes (Isolado)

Em `spec/requests/transactions_spec.rb`, validar:
1. `POST /transactions` (formato `turbo_stream`) cria a transação para `Current.user`, responde `200 OK` com `text/vnd.turbo-stream.html` contendo `prepend "transactions_table_body"`, `replace "dashboard_metrics"` e `update "transaction_form_container"`.
2. `POST /transactions` com `amount <= 0` ou despesa sem `payment_method` recusa o registro e retorna `422 Unprocessable Entity`.
3. `PATCH /transactions/:id` e `DELETE /transactions/:id` atualizam/removem o registro e recalculam `@metrics` no Turbo Stream.
4. **Isolamento Multi-Tenant (`RF-002`)**: tentar `GET /transactions/:id/edit`, `PATCH /transactions/:id` ou `DELETE /transactions/:id` de uma transação pertencente a outro usuário retorna estritamente `HTTP 404 Not Found` e não modifica o banco.

---

## 5. Definition of Done (DoD)

- [ ] `TransactionsController`, templates Turbo Stream e controller Stimulus implementados.
- [ ] `bundle exec rspec spec/requests/transactions_spec.rb` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Atualizar `docs/adrs/ADR-003-server-driven-reactive-ui-with-rails-8-and-hotwire.md` com os contratos de Turbo Stream e Stimulus implementados.
