# frozen_string_literal: true

module Types
  class ExpenseType < GraphQL::Schema::Object
    field :id, ID, null: false
    field :description, String, null: false
    field :amount, Float, null: false
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :category, String, null: true
    field :user, Types::UserType, null: false
    field :wallet, Types::WalletType, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
