# frozen_string_literal: true

module Mutations
  # Atenção: dentro deste módulo a constante RecurringTransaction resolve para o
  # próprio módulo, não para o model. Sempre passar por user.recurring_transactions.
  module RecurringTransaction
    class RecurringTransactionCreate < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :kind, Types::TransactionKindEnum, required: true
      argument :description, String, required: true
      argument :amount, Float, required: true
      argument :day_of_month, Integer, required: true
      argument :start_date, GraphQL::Types::ISO8601Date, required: true
      argument :end_date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false
      argument :wallet_id, ID, required: false

      field :recurring_transaction, Types::RecurringTransactionType, null: true
      field :generated_count, Integer, null: false
      field :errors, [ String ], null: false

      def resolve(kind:, description:, amount:, day_of_month:, start_date:, end_date: nil, category: nil, wallet_id: nil)
        user = authenticated_user!
        wallet = wallet_id ? find_wallet!(user, wallet_id) : user.wallets.first

        template = user.recurring_transactions.build(
          kind: kind, description: description, amount: amount, day_of_month: day_of_month,
          start_date: start_date, end_date: end_date, category: category, wallet: wallet
        )

        if template.save
          # Materializa na hora, senão o usuário envia o formulário e não vê
          # nada mudar na lista — indistinguível de um bug.
          { recurring_transaction: template, generated_count: template.generate_entries!, errors: [] }
        else
          { recurring_transaction: nil, generated_count: 0, errors: template.errors.full_messages }
        end
      end
    end
  end
end
