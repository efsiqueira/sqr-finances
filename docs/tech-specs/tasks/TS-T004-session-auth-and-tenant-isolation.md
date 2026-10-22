# TS-T004: Autenticação de Sessão Dual (Email/Username), Current.user e Isolamento 404

- **Task:** `T-004`
- **Branch:** `feat/T-004-session-auth-and-tenant-isolation`
- **Dependência:** `T-003`
- **Módulos Afetados:** `[AUTH]`, `[WEB]`
- **Requisitos Atendidos:** `RF-001` (Cadastro e Login por Email ou Username), `RF-002` (Isolamento de Dados e Resposta `HTTP 404 Not Found`)
- **ADR Relacionada (Formalizar no DoD):**
  - Rascunho: [logical-multi-tenancy-with-current-user-scoping-and-404-indistinguishability.md](../../adrs/potential-adrs/must-document/AUTH/logical-multi-tenancy-with-current-user-scoping-and-404-indistinguishability.md)
  - Destino Oficial: `docs/adrs/ADR-008-logical-multi-tenancy-and-404-indistinguishability.md`
- **Referências:**
  - [TASKS-001: Backlog do MVP](../../backlog/TASKS-001-mvp-controle-financeiro.md)
  - [PRD-001: MVP de Controle Financeiro](../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md)
  - [HLD-001: Arquitetura Monólito Modular e Hotwire](../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)

---

## 1. Objetivo Técnico

Implementar a camada de autenticação baseada em sessão HTTP, o contexto por requisição via `Current.user` (`ActiveSupport::CurrentAttributes`), os fluxos de cadastro (`RegistrationsController`) e login/logout (`SessionsController`), além da política de segurança de indistinguibilidade (`RF-002`) que responde `HTTP 404 Not Found` para qualquer `ActiveRecord::RecordNotFound` originado de buscas escopadas ao tenant.

---

## 2. Arquivos a Criar / Modificar

- `app/models/current.rb` (Novo)
- `app/controllers/concerns/authentication.rb` (Novo)
- `app/controllers/application_controller.rb` (Inclusão de `Authentication` e tratamento `404`)
- `app/controllers/sessions_controller.rb` (Novo)
- `app/controllers/registrations_controller.rb` (Novo)
- `app/views/sessions/new.html.erb` (Novo)
- `app/views/registrations/new.html.erb` (Novo)
- `config/routes.rb` (Rotas `/login`, `/logout`, `/signup`)
- `spec/requests/authentication_spec.rb` (Novo)

---

## 3. Especificação de Implementação

### 3.1 `app/models/current.rb`

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
```

### 3.2 `app/controllers/concerns/authentication.rb`

```ruby
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    current_user.present?
  end

  def current_user
    Current.user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def require_authentication
    redirect_to login_path, alert: "Faça login para continuar." unless authenticated?
  end

  def start_new_session_for(user)
    reset_session
    session[:user_id] = user.id
    Current.user = user
  end

  def terminate_session
    reset_session
    Current.user = nil
  end
end
```

### 3.3 `app/controllers/application_controller.rb` (Isolamento `404 Not Found` — `RF-002`)

```ruby
class ApplicationController < ActionController::Base
  include Authentication

  allow_browser versions: :modern

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    head :not_found
  end
end
```

### 3.4 `SessionsController` e `RegistrationsController`

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to login_path, alert: "Muitas tentativas. Tente novamente mais tarde." }

  def new; end

  def create
    if (user = User.authenticate_by_login(params[:login], params[:password]))
      start_new_session_for(user)
      redirect_to root_path, notice: "Login realizado com sucesso."
    else
      flash.now[:alert] = "Credenciais inválidas."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to login_path, status: :see_other, notice: "Sessão encerrada."
  end
end
```

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      start_new_session_for(@user)
      redirect_to root_path, notice: "Conta criada com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :username, :email, :password, :password_confirmation)
  end
end
```

### 3.5 Rotas (`config/routes.rb`)

```ruby
Rails.application.routes.draw do
  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get  "signup", to: "registrations#new",    as: :signup
  post "signup", to: "registrations#create"

  get "up" => "rails/health#show", as: :rails_health_check
  root "sessions#new" # Será atualizado para dashboard#index na T-011
end
```

---

## 4. Plano de Testes (Isolado)

Em `spec/requests/authentication_spec.rb`, testar sem depender de `Transaction` ou `Dashboard`:
1. `POST /signup` cria um novo `User`, inicia a sessão (`session[:user_id]`) e redireciona.
2. `POST /login` autentica com sucesso usando `email` e também usando `username`.
3. `POST /login` com senha incorreta retorna `422 Unprocessable Entity` e não cria sessão.
4. `DELETE /logout` limpa a sessão (`reset_session`).
5. Um controller de teste anônimo (ou rota protegida) verifica que:
   - Acesso sem sessão redireciona para `/login`.
   - Acesso autenticado tentando buscar um recurso de outro usuário (disparando `ActiveRecord::RecordNotFound`) retorna exatamente `HTTP 404 Not Found` (`RF-002`).

---

## 5. Definition of Done (DoD)

- [ ] Fluxos de cadastro, login dual (`email` ou `username`) e logout funcionais.
- [ ] `Current.user` hidratado automaticamente em requisições autenticadas.
- [ ] `ActiveRecord::RecordNotFound` tratado com `404 Not Found`.
- [ ] `bundle exec rspec spec/requests/authentication_spec.rb` passa com 0 falhas.
- [ ] Formalizar a `docs/adrs/ADR-008-logical-multi-tenancy-and-404-indistinguishability.md` a partir do rascunho em `potential-adrs/must-document/AUTH/`.
