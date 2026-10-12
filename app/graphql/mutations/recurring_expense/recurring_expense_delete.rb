# frozen_string_literal: true

module Mutations
  module RecurringExpense
    class RecurringExpenseDelete < GraphQL::Schema::Mutation
      argument :id, ID, required: true

      field :recurring_expense, Types::RecurringExpenseType, null: true
      field :errors, [ String ], null: false

      def resolve(id:)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        template = user.recurring_expenses.find(id)
        # dependent: :nullify — os lançamentos já gerados permanecem.
        template.destroy

        { recurring_expense: template, errors: [] }
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Despesa recorrente não encontrada"
      end
    end
  end
end
