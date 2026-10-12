# frozen_string_literal: true

module Mutations
  module Wallet
    # Edita a carteira do usuário autenticado (ele só tem uma, então não há id).
    class WalletUpdate < GraphQL::Schema::Mutation
      include Mutations::Scoped

      argument :name, String, required: false
      argument :initial_balance, Float, required: false

      field :wallet, Types::WalletType, null: true
      field :errors, [ String ], null: false

      def resolve(**attributes)
        wallet = authenticated_user!.wallet

        if wallet.update(attributes.compact)
          { wallet: wallet, errors: [] }
        else
          { wallet: nil, errors: wallet.errors.full_messages }
        end
      end
    end
  end
end
