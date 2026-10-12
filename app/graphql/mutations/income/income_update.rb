# frozen_string_literal: true

module Mutations
  module Income
    class IncomeUpdate < GraphQL::Schema::Mutation
      argument :id, ID, required: true
      argument :description, String, required: false
      argument :amount, Float, required: false
      argument :date, GraphQL::Types::ISO8601Date, required: false
      argument :category, String, required: false
      argument :wallet_id, ID, required: false

      field :income, Types::IncomeType, null: true
      field :errors, [String], null: false

      def resolve(id:, **attributes)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        income = user.incomes.find(id)

        # Sem .compact: o graphql-ruby só entrega no **attributes os argumentos
        # que o cliente de fato enviou, então uma chave presente com nil é um
        # pedido explícito de limpar o campo.
        if attributes.key?(:wallet_id)
          wallet_id = attributes.delete(:wallet_id)
          attributes[:wallet] = wallet_id ? find_wallet!(user, wallet_id) : nil
        end

        if income.update(attributes)
          { income: income, errors: [] }
        else
          { income: nil, errors: income.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Receita não encontrada"
      end

      private

      # Rescue próprio para que uma carteira inexistente não seja reportada
      # como "Receita não encontrada" pelo rescue do resolve.
      def find_wallet!(user, wallet_id)
        user.wallets.find(wallet_id)
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Carteira não encontrada"
      end
    end
  end
end
