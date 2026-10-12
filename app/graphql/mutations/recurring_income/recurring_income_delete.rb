# frozen_string_literal: true

module Mutations
  module RecurringIncome
    class RecurringIncomeDelete < GraphQL::Schema::Mutation
      argument :id, ID, required: true

      field :recurring_income, Types::RecurringIncomeType, null: true
      field :errors, [String], null: false

      def resolve(id:)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        template = user.recurring_incomes.find(id)
        # dependent: :nullify — os lançamentos já gerados permanecem.
        template.destroy

        { recurring_income: template, errors: [] }
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Receita recorrente não encontrada"
      end
    end
  end
end
