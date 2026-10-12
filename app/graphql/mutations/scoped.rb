# frozen_string_literal: true

module Mutations
  # Helpers das mutations que operam sobre dados do usuário autenticado.
  module Scoped
    private

    def authenticated_user!
      context[:current_user] || raise(GraphQL::ExecutionError, "Você precisa estar autenticado")
    end
  end
end
