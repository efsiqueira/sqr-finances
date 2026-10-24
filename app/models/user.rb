# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_many :transactions, dependent: :destroy
  has_many :recurrences, dependent: :destroy

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :username, with: ->(username) { username.to_s.strip.downcase }
  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, length: { maximum: 150 }
  validates :username,
            presence: true,
            length: { minimum: 3, maximum: 50 },
            format: { with: /\A[a-z0-9_.]+\z/, message: "permite apenas letras, números, ponto e sublinhado" },
            uniqueness: { case_sensitive: false }
  validates :email,
            presence: true,
            length: { maximum: 255 },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || !password.nil? }

  def self.authenticate_by_login(login, password)
    normalized = login.to_s.strip.downcase
    return nil if normalized.blank? || password.blank?

    user = find_by("email = :login OR username = :login", login: normalized)
    user&.authenticate(password) || nil
  end
end
