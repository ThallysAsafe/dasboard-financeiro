# frozen_string_literal: true

module Mutations
  module Wallet
    class WalletDelete < GraphQL::Schema::Mutation
      argument :id, ID, required: true

      field :wallet, Types::WalletType, null: true
      field :errors, [String], null: false

      def resolve(id:)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        wallet = user.wallets.find(id)
        if wallet.destroy
          { wallet: wallet, errors: [] }
        else
          { wallet: nil, errors: wallet.errors.full_messages }
        end
      rescue ActiveRecord::RecordNotFound
        raise GraphQL::ExecutionError, "Carteira não encontrada"
      end
    end
  end
end
