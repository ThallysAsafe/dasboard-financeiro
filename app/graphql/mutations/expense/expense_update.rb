# frozen_string_literal: true

module Mutations
  module Expense
    class ExpenseUpdate < GraphQL::Schema::Mutation
      argument :id, ID, required: true
      argument :description, String, required: false
      argument :amount, Float, required: false
      argument :date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false

      field :expense, Types::ExpenseType, null: true
      field :errors, [String], null: false

      def resolve(id:, **attributes)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        expense = user.expenses.find(id)
        if expense.update(attributes.compact)
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
