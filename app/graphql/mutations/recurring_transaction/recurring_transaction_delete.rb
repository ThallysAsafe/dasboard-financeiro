# frozen_string_literal: true

module Mutations
  module RecurringTransaction
    class RecurringTransactionDelete < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :id, ID, required: true

      field :recurring_transaction, Types::RecurringTransactionType, null: true
      field :errors, [ String ], null: false

      def resolve(id:)
        user = authenticated_user!
        template = user.recurring_transactions.find(id)
        # dependent: :nullify — os lançamentos já gerados permanecem.
        template.destroy

        { recurring_transaction: template, errors: [] }
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Recorrência não encontrada"
      end
    end
  end
end
