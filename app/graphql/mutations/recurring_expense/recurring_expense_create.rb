# frozen_string_literal: true

module Mutations
  module RecurringExpense
    # Atenção: dentro deste módulo a constante RecurringExpense resolve para o
    # próprio módulo, não para o model. Sempre passar por user.recurring_expenses.
    class RecurringExpenseCreate < GraphQL::Schema::Mutation
      argument :description, String, required: true
      argument :amount, Float, required: true
      argument :day_of_month, Integer, required: true
      argument :start_date, GraphQL::Types::ISO8601Date, required: true
      argument :end_date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false
      argument :wallet_id, ID, required: false

      field :recurring_expense, Types::RecurringExpenseType, null: true
      field :generated_count, Integer, null: false
      field :errors, [String], null: false

      def resolve(description:, amount:, day_of_month:, start_date:, end_date: nil, category: nil, wallet_id: nil)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        wallet = wallet_id ? user.wallets.find(wallet_id) : user.wallets.first

        template = user.recurring_expenses.build(
          description: description,
          amount: amount,
          day_of_month: day_of_month,
          start_date: start_date,
          end_date: end_date,
          category: category,
          wallet: wallet
        )

        if template.save
          { recurring_expense: template, generated_count: template.generate_entries!, errors: [] }
        else
          { recurring_expense: nil, generated_count: 0, errors: template.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Carteira não encontrada"
      end
    end
  end
end
