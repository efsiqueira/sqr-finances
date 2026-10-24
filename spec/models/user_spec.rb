# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  describe "schema & ADR-001 compliance" do
    it "does not include any static balance columns" do
      expect(described_class.column_names).not_to include("balance", "current_balance")
    end
  end

  describe "associations" do
    it "defines has_many transactions with dependent destroy" do
      association = described_class.reflect_on_association(:transactions)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "defines has_many recurrences with dependent destroy" do
      association = described_class.reflect_on_association(:recurrences)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "validations" do
    it { is_expected.to have_secure_password }

    describe "name" do
      it { is_expected.to validate_presence_of(:name) }
      it { is_expected.to validate_length_of(:name).is_at_most(150) }
    end

    describe "username" do
      it { is_expected.to validate_presence_of(:username) }
      it { is_expected.to validate_length_of(:username).is_at_least(3).is_at_most(50) }

      it "validates uniqueness case-insensitively" do
        create(:user, username: "valid.user_1")
        duplicate = build(:user, username: "VALID.USER_1")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:username]).to include("has already been taken")
      end

      it "accepts valid characters (letters, numbers, dot, underscore)" do
        valid_usernames = %w[john.doe john_doe user123 456user a.b_c]
        valid_usernames.each do |valid_username|
          user.username = valid_username
          user.valid?
          expect(user.errors[:username]).to be_empty
        end
      end

      it "rejects invalid characters" do
        invalid_usernames = [ "john doe", "user@name", "user!", "user#name", "user-name" ]
        invalid_usernames.each do |invalid_username|
          user.username = invalid_username
          expect(user).not_to be_valid
          expect(user.errors[:username]).to include("permite apenas letras, números, ponto e sublinhado")
        end
      end
    end

    describe "email" do
      it { is_expected.to validate_presence_of(:email) }
      it { is_expected.to validate_length_of(:email).is_at_most(255) }

      it "validates uniqueness case-insensitively" do
        create(:user, email: "ada@sqrfinance.dev")
        duplicate = build(:user, email: "ADA@sqrfinance.dev")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:email]).to include("has already been taken")
      end

      it "accepts valid email formats" do
        valid_emails = %w[user@example.com first.last@sub.domain.org user+tag@domain.co]
        valid_emails.each do |valid_email|
          user.email = valid_email
          user.valid?
          expect(user.errors[:email]).to be_empty
        end
      end

      it "rejects invalid email formats" do
        invalid_emails = [ "invalid_email", "user@", "@domain.com", "user@@domain.com", "user name@domain.com" ]
        invalid_emails.each do |invalid_email|
          user.email = invalid_email
          expect(user).not_to be_valid
          expect(user.errors[:email]).to be_present
        end
      end
    end

    describe "password" do
      it { is_expected.to validate_length_of(:password).is_at_least(8) }

      it "allows updating user attributes without re-specifying password" do
        persisted_user = create(:user)
        expect(persisted_user.update(name: "New Name")).to be(true)
      end
    end
  end

  describe "normalizations" do
    it "normalizes email by stripping whitespace and downcasing" do
      user = create(:user, email: "  ADA.Lovelace@SQRFinance.DEV  ")
      expect(user.email).to eq("ada.lovelace@sqrfinance.dev")
    end

    it "normalizes username by stripping whitespace and downcasing" do
      user = create(:user, username: "  Ada_Lovelace.01  ")
      expect(user.username).to eq("ada_lovelace.01")
    end

    it "normalizes name by stripping whitespace" do
      user = create(:user, name: "   Ada Lovelace   ")
      expect(user.name).to eq("Ada Lovelace")
    end
  end

  describe "database unique constraints" do
    it "raises ActiveRecord::RecordNotUnique on duplicate username when bypassing validation" do
      create(:user, username: "unique_user")
      duplicate = build(:user, username: "unique_user")

      expect do
        duplicate.save(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "raises ActiveRecord::RecordNotUnique on duplicate email when bypassing validation" do
      create(:user, email: "unique@sqrfinance.dev")
      duplicate = build(:user, email: "unique@sqrfinance.dev")

      expect do
        duplicate.save(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".authenticate_by_login" do
    let!(:existing_user) do
      create(:user,
             username: "ada_lovelace",
             email: "ada@sqrfinance.dev",
             password: "Password123!",
             password_confirmation: "Password123!")
    end

    context "when authenticating by email" do
      it "returns the user when email and password match" do
        result = described_class.authenticate_by_login("ada@sqrfinance.dev", "Password123!")
        expect(result).to eq(existing_user)
      end

      it "is case-insensitive and trims whitespace" do
        result = described_class.authenticate_by_login("  ADA@sqrfinance.dev  ", "Password123!")
        expect(result).to eq(existing_user)
      end
    end

    context "when authenticating by username" do
      it "returns the user when username and password match" do
        result = described_class.authenticate_by_login("ada_lovelace", "Password123!")
        expect(result).to eq(existing_user)
      end

      it "is case-insensitive and trims whitespace" do
        result = described_class.authenticate_by_login("  ADA_LOVELACE  ", "Password123!")
        expect(result).to eq(existing_user)
      end
    end

    context "when authentication fails" do
      it "returns nil when password is incorrect" do
        result = described_class.authenticate_by_login("ada_lovelace", "WrongPass999!")
        expect(result).to be_nil
      end

      it "returns nil when login does not exist" do
        result = described_class.authenticate_by_login("non_existent_user", "Password123!")
        expect(result).to be_nil
      end

      it "returns nil when login is blank" do
        expect(described_class.authenticate_by_login("", "Password123!")).to be_nil
        expect(described_class.authenticate_by_login(nil, "Password123!")).to be_nil
        expect(described_class.authenticate_by_login("   ", "Password123!")).to be_nil
      end

      it "returns nil when password is blank" do
        expect(described_class.authenticate_by_login("ada_lovelace", "")).to be_nil
        expect(described_class.authenticate_by_login("ada_lovelace", nil)).to be_nil
      end
    end
  end
end
