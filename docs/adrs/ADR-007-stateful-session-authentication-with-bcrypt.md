# ADR-007: Stateful Session-Based Authentication with Rails has_secure_password (bcrypt) and Dual-Identifier Credentials

- **Status:** Accepted
- **Date:** 2026-10-24
- **Module:** `[AUTH]`
- **Category:** Security / Architecture
- **Deciders:** Sqr Finances Core Architecture Team
- **Related ADRs:**
  - [ADR-001: Saldo Derivado Dinamicamente (`AGG` / `DATA`)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)
  - [ADR-003: Arquitetura Orientada ao Servidor (Hotwire)](../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md#4-decisões-arquiteturais-fundamentais-adrs)
  - [ADR-005: PostgreSQL 16 as Authoritative ACID Datastore](./ADR-005-postgresql-16-authoritative-acid-datastore.md)

---

## 1. Context and Problem Statement

Sqr Finances is a reactive financial control monolith built with Ruby on Rails 8 and Hotwire (ADR-003). As defined in functional requirement **RF-001** (`docs/PRD-001.md`), users must register with unique credentials (`email` and `username`) and authenticate into the application seamlessly using either identifier alongside a secure password.

Traditional modern web applications frequently opt for externalized identity providers (such as Auth0, Clerk, AWS Cognito) or stateless JSON Web Tokens (JWT) stored in browser storage (e.g., LocalStorage or HTTP cookies). However:
1. **External Identity Providers** introduce third-party vendor lock-in, recurring operating costs, and external network round-trips for every authentication request.
2. **Stateless JWTs** in a server-rendered Hotwire application add unnecessary complexity regarding token refresh cycles, client-side header injection across Turbo Drive/Turbo Frame navigations, and token invalidation revocation challenges upon logout.
3. Because all application interfaces are server-rendered via Hotwire (Turbo Drive, Turbo Frames, Turbo Streams), HTTP cookie-based session management integrates natively with the browser and Rails request pipeline.

A cohesive, secure, and self-contained identity and authentication strategy is required to support dual-identifier login, case-insensitive uniqueness, robust password hashing, and clean integration with request-scoped authorization.

---

## 2. Decision Drivers

- **Simplicity and Self-Containment**: Eliminate external identity dependencies, third-party authentication latency, and unnecessary SaaS costs.
- **Hotwire Cohesion**: Provide seamless session handling across Turbo Drive, Turbo Frames, and Turbo Streams using encrypted HTTP-only session cookies.
- **Dual-Identifier Login (RF-001)**: Permit users to log in interchangeably with their registered `email` or `username`.
- **Defense-in-Depth Identity Invariants**: Guarantee strict credential uniqueness and formatting at both the application level (`ActiveRecord` validations and normalizations) and the database schema level (`PostgreSQL` unique indexes).
- **Security Best Practices**: Employ adaptive, slow, salted one-way password hashing via standard `bcrypt` to protect against offline rainbow-table and brute-force attacks.
- **Zero Balance Leakage (ADR-001)**: Maintain the `users` table purely for identity and credentials without any static financial balance state.

---

## 3. Considered Options

1. **Native Rails 8 `has_secure_password` (`bcrypt`) + Dual-Identifier Lookup (Chosen)**
2. **Heavyweight Rails Authentication Engines (e.g., Devise)**
3. **External Identity as a Service (e.g., Auth0, Clerk, Cognito)**
4. **Stateless JWT Bearer Authentication**

---

## 4. Decision

We chose **native Rails 8 `has_secure_password` backed by `bcrypt` (~> 3.1.7)** combined with a dual-identifier credential strategy in the `User` model and stateful encrypted HTTP cookie sessions.

Specifically, the architecture establishes the following standards:

### 4.1 Schema Definition & PostgreSQL Integrity
The `users` table is defined in PostgreSQL 16 with explicit length constraints, timestamps with server default (`NOW()`), and case-insensitive unique indexes:

```ruby
create_table :users do |t|
  t.string :name, limit: 150, null: false
  t.string :username, limit: 50, null: false
  t.string :email, limit: 255, null: false
  t.string :password_digest, limit: 255, null: false

  t.timestamps null: false, default: -> { "NOW()" }
end

add_index :users, :username, unique: true
add_index :users, :email, unique: true
```

No static financial balance columns (`balance`, `current_balance`) are included, preserving strict compliance with `ADR-001`.

### 4.2 Credential Normalization & Validations
To prevent subtle authentication mismatches due to capitalization or trailing whitespace, Rails 8 `normalizes` is applied before saving or querying:
- `email`: stripped and lowercased (`email.to_s.strip.downcase`).
- `username`: stripped and lowercased (`username.to_s.strip.downcase`).
- `name`: stripped of surrounding whitespace (`name.to_s.strip`).

Validation rules:
- `username`: 3 to 50 characters, format restricted to `/\A[a-z0-9_.]+\z/` (letters, numbers, dot, underscore), case-insensitive uniqueness.
- `email`: maximum 255 characters, valid email regex (`URI::MailTo::EMAIL_REGEXP`), case-insensitive uniqueness.
- `password`: minimum 8 characters enforced on create or when password is explicitly updated.

### 4.3 Dual-Identifier Authentication (`.authenticate_by_login`)
To satisfy requirement **RF-001**, the `User` domain model encapsulates credential lookup:
```ruby
def self.authenticate_by_login(login, password)
  normalized = login.to_s.strip.downcase
  return nil if normalized.blank? || password.blank?

  user = find_by("email = :login OR username = :login", login: normalized)
  user&.authenticate(password) || nil
end
```
`User#authenticate` uses `BCrypt::Password.new(password_digest).is_password?(password)` ensuring constant-time comparison that resists timing attacks.

---

## 5. Consequences

### Positive
- **Zero Third-Party Dependency**: Entire authentication lifecycle runs within the Rails monolith and local PostgreSQL 16 container.
- **Native Hotwire Compatibility**: Authentication cookies persist across Turbo Drive visits and Turbo Stream submissions with standard Rails CSRF protection (`protect_from_forgery`).
- **Flexible UX**: Users can sign in using whichever credential they remember (email or username).
- **Defense in Depth**: Prevents duplicate accounts at the PostgreSQL database index level even if application validations are bypassed.

### Negative / Trade-offs
- **Self-Managed Security Perimeter**: Password reset workflows, rate limiting against brute-force attacks, and session invalidation must be implemented and maintained by the application codebase.
- **Single Monolith Scope**: If native mobile clients or external public APIs are added in future iterations, token-based authentication (e.g., API keys or OAuth2) will need to be introduced alongside the session cookies.

---

## 6. Implementation Notes & Validation

- Gem `bcrypt ~> 3.1.7` enabled in `Gemfile`.
- Migration `db/migrate/20261024230524_create_users.rb` executed and recorded in `db/schema.rb`.
- Model implemented in `app/models/user.rb`.
- Factory defined in `spec/factories/users.rb`.
- Unit tests implemented in `spec/models/user_spec.rb` verifying ADR-001 compliance, validations, normalizations, unique database constraints, and dual-identifier authentication behaviors.

---

## 7. References

- [PRD-001: MVP de Controle Financeiro](../../prds/PRD-001-mvp-controle-financeiro-fluxo-caixa.md) - Requisito RF-001
- [HLD-001: Arquitetura Monólito Modular Hotwire](../../hlds/HLD-001-arquitetura-monolito-modular-hotwire.md)
- [TS-T003: Migration e Model de Usuário](../tech-specs/tasks/TS-T003-user-model-and-migration.md)
- [Draft ADR: stateful-session-authentication-with-bcrypt.md](./potential-adrs/must-document/AUTH/stateful-session-authentication-with-bcrypt.md)
