# frozen_string_literal: true

module Mutations
  module Wallet
    class WalletCreate < GraphQL::Schema::Mutation
      argument :name, String, required: true
      argument :initial_balance, Float, required: false, default_value: 0.0

      field :wallet, Types::WalletType, null: true
      field :errors, [String], null: false

      def resolve(name:, initial_balance: 0.0)
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        wallet = user.wallets.build(name: name, initial_balance: initial_balance)

        if wallet.save
          { wallet: wallet, errors: [] }
        else
          { wallet: nil, errors: wallet.errors.full_messages }
        end
      end
    end
  end
end
