# frozen_string_literal: true

module Mutations
  module Transaction
    # O tipo (receita/despesa) não muda depois de criado: seria reclassificar
    # dinheiro. Para isso, exclua e crie de novo.
    class TransactionUpdate < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :id, ID, required: true
      argument :description, String, required: false
      argument :amount, Float, required: false
      argument :date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false

      field :transaction, Types::TransactionType, null: true
      field :errors, [ String ], null: false

      def resolve(id:, **attributes)
        user = authenticated_user!
        transaction = user.transactions.find(id)

        if transaction.update(attributes)
          { transaction: transaction, errors: [] }
        else
          { transaction: nil, errors: transaction.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Lançamento não encontrado"
      end
    end
  end
end
