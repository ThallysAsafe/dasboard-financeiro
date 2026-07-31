# frozen_string_literal: true

module Mutations
  module Expense
    class ExpenseCreate < GraphQL::Schema::Mutation
      argument :description, String, required: true
      argument :amount, Float, required: true
      argument :date, GraphQL::Types::ISO8601Date, required: true
      argument :category, String, required: false

      field :expense, Types::ExpenseType, null: true
      field :errors, [String], null: false

      def resolve(description:, amount:, date:, category: nil)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        expense = user.expenses.build(
          description: description,
          amount: amount,
          date: date,
          category: category
        )

        if expense.save
          { expense: expense, errors: [] }
        else
          { expense: nil, errors: expense.errors.full_messages }
        end
      end
    end
  end
end
