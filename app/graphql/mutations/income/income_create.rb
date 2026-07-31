# frozen_string_literal: true

module Mutations
  module Income
    class IncomeCreate < GraphQL::Schema::Mutation
      argument :description, String, required: true
      argument :amount, Float, required: true
      argument :date, GraphQL::Types::ISO8601Date, required: true
      argument :category, String, required: false

      field :income, Types::IncomeType, null: true
      field :errors, [String], null: false

      def resolve(description:, amount:, date:, category: nil)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        income = user.incomes.build(
          description: description,
          amount: amount,
          date: date,
          category: category
        )

        if income.save
          { income: income, errors: [] }
        else
          { income: nil, errors: income.errors.full_messages }
        end
      end
    end
  end
end
