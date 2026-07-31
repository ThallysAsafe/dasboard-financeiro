# frozen_string_literal: true

module Mutations
  module Income
    class IncomeDelete < GraphQL::Schema::Mutation
      argument :id, ID, required: true

      field :income, Types::IncomeType, null: true
      field :errors, [String], null: false

      def resolve(id:)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        income = user.incomes.find(id)
        if income.destroy
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
