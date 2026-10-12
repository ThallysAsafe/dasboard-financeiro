# frozen_string_literal: true

module Types
  class IncomeType < GraphQL::Schema::Object
    field :id, ID, null: false
    field :description, String, null: false
    field :amount, Float, null: false
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :category, String, null: true
    field :recurring_income_id, ID, null: true, description: "Preenchido quando o lançamento veio de uma recorrência"
    field :user, Types::UserType, null: false
    field :wallet, Types::WalletType, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    # Todo registro exposto pertence ao usuário autenticado; evita um
    # SELECT de usuário por linha (N+1).
    def user
      context[:current_user]
    end
  end
end
