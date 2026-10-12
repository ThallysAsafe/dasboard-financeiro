# frozen_string_literal: true

module Mutations
  module RecurringTransaction
    class RecurringTransactionUpdate < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :id, ID, required: true
      argument :description, String, required: false
      argument :amount, Float, required: false
      argument :day_of_month, Integer, required: false
      argument :start_date, GraphQL::Types::ISO8601Date, required: false
      argument :end_date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false
      argument :active, Boolean, required: false

      field :recurring_transaction, Types::RecurringTransactionType, null: true
      field :generated_count, Integer, null: false
      field :errors, [ String ], null: false

      def resolve(id:, **attributes)
        user = authenticated_user!
        template = user.recurring_transactions.find(id)

        if template.update(attributes)
          { recurring_transaction: template, generated_count: template.generate_entries!, errors: [] }
        else
          { recurring_transaction: nil, generated_count: 0, errors: template.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Recorrência não encontrada"
      end
    end
  end
end
