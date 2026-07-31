# frozen_string_literal: true

module Mutations
  module Expense
    class ExpenseDelete < GraphQL::Schema::Mutation
      argument :id, ID, required: true

      field :expense, Types::ExpenseType, null: true
      field :errors, [String], null: false

      def resolve(id:)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        expense = user.expenses.find(id)
        if expense.destroy
          { expense: expense, errors: [] }
        else
          { expense: nil, errors: expense.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Despesa não encontrada"
      end
    end
  end
end
