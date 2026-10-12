# frozen_string_literal: true

module Mutations
  module Recurring
    # Materializa os lançamentos devidos de todos os templates ativos.
    #
    # É uma mutation e não um efeito colateral dentro das queries: o dashboard
    # pede balance, totalIncome, incomes e expenses na mesma requisição, então
    # pendurar a geração em campos de query a faria rodar várias vezes por
    # carregamento — e ainda dispararia em qualquer leitura, inclusive nos testes.
    class SyncRecurringEntries < GraphQL::Schema::Mutation
      field :created_count, Integer, null: false
      field :errors, [ String ], null: false

      def resolve
        user = context[:current_user]
        raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless user

        { created_count: user.sync_recurring_entries!, errors: [] }
      end
    end
  end
end
