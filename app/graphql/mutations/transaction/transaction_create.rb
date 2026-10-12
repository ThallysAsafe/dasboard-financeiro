# frozen_string_literal: true

module Mutations
  # Atenção: dentro deste módulo a constante Transaction resolve para o próprio
  # módulo, não para o model. Sempre passar por user.transactions.
  module Transaction
    class TransactionCreate < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :kind, Types::TransactionKindEnum, required: true
      argument :description, String, required: true
      argument :amount, Float, required: true
      argument :date, GraphQL::Types::ISO8601Date, required: true
      argument :category, String, required: false

      field :transaction, Types::TransactionType, null: true
      field :errors, [ String ], null: false

      def resolve(kind:, description:, amount:, date:, category: nil)
        user = authenticated_user!
        transaction = user.transactions.build(
          kind: kind, description: description, amount: amount,
          date: date, category: category
        )

        if transaction.save
          { transaction: transaction, errors: [] }
        else
          { transaction: nil, errors: transaction.errors.full_messages }
        end
      end
    end
  end
end
