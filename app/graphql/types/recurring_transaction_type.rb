# frozen_string_literal: true

module Types
  class RecurringTransactionType < GraphQL::Schema::Object
    field :id, ID, null: false
    field :kind, Types::TransactionKindEnum, null: false
    field :description, String, null: false
    field :amount, Float, null: false
    field :day_of_month, Integer, null: false, description: "Dia do mês em que o lançamento acontece (travado no último dia em meses curtos)"
    field :start_date, GraphQL::Types::ISO8601Date, null: false
    field :end_date, GraphQL::Types::ISO8601Date, null: true, description: "Data final da recorrência; nulo significa sem prazo"
    field :category, String, null: true
    field :active, Boolean, null: false
    field :last_generated_on, GraphQL::Types::ISO8601Date, null: true
    field :next_occurrence, GraphQL::Types::ISO8601Date, null: true, description: "Próxima data em que um lançamento será gerado"
    field :user, Types::UserType, null: false
    field :wallet, Types::WalletType, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def user
      context[:current_user]
    end

    def next_occurrence
      object.next_occurrence
    end
  end
end
