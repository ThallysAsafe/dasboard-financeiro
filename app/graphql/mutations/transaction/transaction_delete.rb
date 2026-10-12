# frozen_string_literal: true

module Mutations
  module Transaction
    class TransactionDelete < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :id, ID, required: true

      field :transaction, Types::TransactionType, null: true
      field :errors, [ String ], null: false

      def resolve(id:)
        user = authenticated_user!
        transaction = user.transactions.find(id)

        if transaction.destroy
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
