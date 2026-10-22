# TS-T013: CRUD Reativo e Gestão de Ciclo de Vida de Recorrências (RF-004, RF-006)

- **Task:** `T-013`
- **Branch:** `feat/T-013-recurrences-crud-and-lifecycle-ui`
- **Dependência:** `T-004, T-006`
- **Módulos Afetados:** `[WEB]`, `[REC]`
- **Requisitos Atendidos:** `RF-002` (Isolamento `404 Not Found`), `RF-004` (Configuração de Regras de Recorrência), `RF-006` (Imutabilidade do Histórico e Soft-Delete na Exclusão)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [thin-controllers-with-stateless-domain-service-objects.md](../../adrs/potential-adrs/consider/WEB/thin-controllers-with-stateless-domain-service-objects.md)
  - Destino Oficial: `docs/adrs/ADR-011-thin-controllers-with-stateless-domain-service-objects.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [TS-001: Mecanismo de Movimentações, Recorrências e Agregação](../TS-001-movimentacoes-recorrencias-agregacao.md)

---

## 1. Objetivo Técnico

Implementar o `RecurrencesController` e as views Hotwire para listagem, criação, edição, pausa/reativação e exclusão lógica (`soft_delete!`) de regras de recorrência escopadas em `Current.user.recurrences.not_deleted`, garantindo que edições ou exclusões afetem exclusivamente ciclos futuros e preservem transações e execuções passadas.

---

## 2. Arquivos a Criar / Modificar

- `app/controllers/recurrences_controller.rb` (Novo)
- `app/views/recurrences/index.html.erb` (Novo)
- `app/views/recurrences/_form.html.erb` (Novo — reutilizando o Stimulus `transaction-type` para `payment_method`)
- `app/views/recurrences/_recurrence.html.erb` (Novo)
- `app/views/recurrences/create.turbo_stream.erb` (Novo)
- `app/views/recurrences/update.turbo_stream.erb` (Novo)
- `app/views/recurrences/destroy.turbo_stream.erb` (Novo)
- `config/routes.rb` (`resources :recurrences` + member action `patch :toggle_active`)
- `spec/requests/recurrences_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/controllers/recurrences_controller.rb`

```ruby
class RecurrencesController < ApplicationController
  before_action :set_recurrence, only: %i[edit update destroy toggle_active]

  def index
    @recurrences = Current.user.recurrences.not_deleted.order(created_at: :desc)
    @recurrence = Current.user.recurrences.new(start_date: Date.current, transaction_type: "expense", frequency: "monthly")
  end

  def create
    @recurrence = Current.user.recurrences.new(recurrence_params)

    if @recurrence.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to recurrences_path, notice: "Regra de recorrência criada." }
      end
    else
      @recurrences = Current.user.recurrences.not_deleted.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @recurrence.update(recurrence_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to recurrences_path, notice: "Regra de recorrência atualizada." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle_active
    @recurrence.update!(active: !@recurrence.active?)
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to recurrences_path, notice: "Status da recorrência atualizado." }
    end
  end

  def destroy
    @recurrence.soft_delete!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to recurrences_path, status: :see_other, notice: "Regra de recorrência removida." }
    end
  end

  private

  def set_recurrence
    @recurrence = Current.user.recurrences.not_deleted.find(params[:id])
  end

  def recurrence_params
    params.require(:recurrence).permit(
      :title,
      :amount,
      :transaction_type,
      :payment_method,
      :frequency,
      :start_date,
      :end_date,
      :active
    )
  end
end
```

### 3.2 Rotas (`config/routes.rb`)

```ruby
resources :recurrences, only: %i[index create edit update destroy] do
  member do
    patch :toggle_active
  end
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/requests/recurrences_spec.rb`, validar:
1. `GET /recurrences` lista apenas as regras de `Current.user` onde `deleted_at IS NULL`.
2. `POST /recurrences` cria uma regra periódica (`weekly`, `monthly`, `yearly`) válida e recusa valores `<= 0` ou `end_date < start_date` com `422 Unprocessable Entity`.
3. `PATCH /recurrences/:id/toggle_active` alterna o estado entre `Ativa` (`active: true`) e `Pausada` (`active: false`).
4. **Imutabilidade e Soft-Delete (`RF-006`)**: `DELETE /recurrences/:id` preenche `deleted_at` e muda `active` para `false` sem apagar o registro do banco e mantendo 100% das transações históricas do usuário intactas.
5. **Isolamento Multi-Tenant (`RF-002`)**: acessar, editar, pausar ou excluir uma recorrência de outro usuário (ou já excluída logicamente) retorna `HTTP 404 Not Found`.

---

## 5. Definition of Done (DoD)

- [ ] `RecurrencesController`, rotas e views Hotwire implementados.
- [ ] `bundle exec rspec spec/requests/recurrences_spec.rb` passa com 0 falhas.
- [ ] `bundle exec rubocop` sem ofensas.
- [ ] Formalizar a `docs/adrs/ADR-011-thin-controllers-with-stateless-domain-service-objects.md` a partir do rascunho em `potential-adrs/consider/WEB/`.
