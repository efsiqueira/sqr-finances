# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :name, limit: 150, null: false
      t.string :username, limit: 50, null: false
      t.string :email, limit: 255, null: false
      t.string :password_digest, limit: 255, null: false

      t.timestamps null: false, default: -> { "NOW()" }
    end

    add_index :users, :username, unique: true
    add_index :users, :email, unique: true
  end
end
