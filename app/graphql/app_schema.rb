# frozen_string_literal: true

class AppSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # For batch-loading (see https://graphql-ruby.org/dataloader/overview.html)
  use GraphQL::Dataloader

  # Limit the size of incoming queries:
  max_query_string_tokens(5000)

  # Wallet -> incomes -> wallet -> incomes... é um ciclo no grafo: sem limite de
  # profundidade, um cliente monta uma query exponencialmente cara. O dashboard
  # usa profundidade 3.
  max_depth 8, count_introspection_fields: false
  max_complexity 300

  # Stop validating when it encounters this many errors:
  validate_max_errors(100)

  # Este schema não usa interfaces/uniões nem Relay Node. Se um dia usar,
  # `object_from_id` (GlobalID.find) precisa ser escopado ao usuário
  # autenticado, ou vira acesso a qualquer registro por ID.
end
