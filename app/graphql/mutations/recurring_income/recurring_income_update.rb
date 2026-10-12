# frozen_string_literal: true

module Mutations
  module RecurringIncome
    class RecurringIncomeUpdate < GraphQL::Schema::Mutation
      argument :id, ID, required: true
      argument :description, String, required: false
      argument :amount, Float, required: false
      argument :day_of_month, Integer, required: false
      argument :start_date, GraphQL::Types::ISO8601Date, required: false
      argument :end_date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false
      argument :active, Boolean, required: false
      argument :wallet_id, ID, required: false

      field :recurring_income, Types::RecurringIncomeType, null: true
      field :generated_count, Integer, null: false
      field :errors, [ String ], null: false

      def resolve(id:, **attributes)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        template = user.recurring_incomes.find(id)

        # Sem .compact: o graphql-ruby só entrega no **attributes os argumentos
        # que o cliente de fato enviou, então uma chave presente com nil é um
        # pedido explícito de limpar o campo (ex.: tirar o prazo final).
        if attributes.key?(:wallet_id)
          wallet_id = attributes.delete(:wallet_id)
          attributes[:wallet] = wallet_id ? find_wallet!(user, wallet_id) : nil
        end

        if template.update(attributes)
          { recurring_income: template, generated_count: template.generate_entries!, errors: [] }
        else
          { recurring_income: nil, generated_count: 0, errors: template.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Receita recorrente não encontrada"
      end

      private

      def find_wallet!(user, wallet_id)
        user.wallets.find(wallet_id)
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Carteira não encontrada"
      end
    end
  end
end
