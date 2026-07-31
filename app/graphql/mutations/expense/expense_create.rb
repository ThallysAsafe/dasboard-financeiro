# frozen_string_literal: true

module Mutations
  module Expense
    class ExpenseCreate < GraphQL::Schema::Mutation
      argument :description, String, required: true
      argument :amount, Float, required: true
      argument :date, GraphQL::Types::ISO8601Date, required: true
      argument :category, String, required: false
      argument :wallet_id, ID, required: false

      field :expense, Types::ExpenseType, null: true
      field :errors, [String], null: false

      def resolve(description:, amount:, date:, category: nil, wallet_id: nil)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        wallet = wallet_id ? user.wallets.find(wallet_id) : user.wallets.first

        expense = user.expenses.build(
          description: description,
          amount: amount,
          date: date,
          category: category,
          wallet: wallet
        )

        if expense.save
          { expense: expense, errors: [] }
        else
          { expense: nil, errors: expense.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Carteira não encontrada"
      end
    end
  end
end
