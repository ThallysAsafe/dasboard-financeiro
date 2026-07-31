# frozen_string_literal: true

module Mutations
  module Income
    class IncomeUpdate < GraphQL::Schema::Mutation
      argument :id, ID, required: true
      argument :description, String, required: false
      argument :amount, Float, required: false
      argument :date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false

      field :income, Types::IncomeType, null: true
      field :errors, [String], null: false

      def resolve(id:, **attributes)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        income = user.incomes.find(id)
        if income.update(attributes.compact)
          { income: income, errors: [] }
        else
          { income: nil, errors: income.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Receita não encontrada"
      end
    end
  end
end
