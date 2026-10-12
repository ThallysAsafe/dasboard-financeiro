# frozen_string_literal: true

module Types
  class WalletType < GraphQL::Schema::Object
    include Types::Pagination

    field :id, ID, null: false
    field :name, String, null: false
    field :initial_balance, Float, null: false
    field :total_income, Float, null: false
    field :total_expense, Float, null: false
    field :balance, Float, null: false
    field :user, Types::UserType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    field :transactions, [ Types::TransactionType ], null: false,
          description: "Lançamentos da carteira, do mais recente ao mais antigo (paginado)" do
      argument :kind, Types::TransactionKindEnum, required: false
      argument :limit, Integer, required: false, default_value: Types::Pagination::DEFAULT_PAGE_SIZE,
               description: "Máximo de #{Types::Pagination::MAX_PAGE_SIZE}"
      argument :offset, Integer, required: false, default_value: 0
    end

    # Todo registro exposto pertence ao usuário autenticado; evita um
    # SELECT de usuário por linha (N+1).
    def user
      context[:current_user]
    end

    def transactions(limit:, offset:, kind: nil)
      scope = object.transactions
      scope = scope.where(kind: kind) if kind
      paginate(scope.order(date: :desc, id: :desc), limit, offset)
    end
  end
end
