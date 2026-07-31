# frozen_string_literal: true

module Types
  class WalletType < GraphQL::Schema::Object
    field :id, ID, null: false
    field :name, String, null: false
    field :initial_balance, Float, null: false
    field :total_income, Float, null: false
    field :total_expense, Float, null: false
    field :balance, Float, null: false
    field :user, Types::UserType, null: false
    field :incomes, [Types::IncomeType], null: false
    field :expenses, [Types::ExpenseType], null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
