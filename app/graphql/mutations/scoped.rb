# frozen_string_literal: true

module Mutations
  # Helpers das mutations que operam sobre dados do usuário autenticado.
  module Scoped
    private

    def authenticated_user!
      context[:current_user] || raise(GraphQL::ExecutionError, "Você precisa estar autenticado")
    end

    # Rescue próprio para que uma carteira inexistente não seja reportada como
    # "não encontrado" pelo rescue do recurso principal da mutation.
    def find_wallet!(user, wallet_id)
      user.wallets.find(wallet_id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Carteira não encontrada"
    end

    # Sem .compact: o graphql-ruby só entrega no **attributes os argumentos que o
    # cliente de fato enviou, então `wallet_id` presente com nil é um pedido
    # explícito de tirar a carteira. Troca `wallet_id` por `wallet` (já validada
    # como sendo do usuário) quando o cliente o enviou.
    def with_wallet(user, attributes)
      return attributes unless attributes.key?(:wallet_id)

      wallet_id = attributes[:wallet_id]
      attributes.except(:wallet_id).merge(wallet: wallet_id ? find_wallet!(user, wallet_id) : nil)
    end
  end
end
