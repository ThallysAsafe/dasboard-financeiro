# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    field :node, Types::NodeType, null: true, description: "Fetches an object given its ID." do
      argument :id, ID, required: true, description: "ID of the object."
    end

    def node(id:)
      context.schema.object_from_id(id, context)
    end

    field :nodes, [Types::NodeType, null: true], null: true, description: "Fetches a list of objects given a list of IDs." do
      argument :ids, [ID], required: true, description: "IDs of the objects."
    end

    def nodes(ids:)
      ids.map { |id| context.schema.object_from_id(id, context) }
    end

    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    # Query: Perfil do usuário autenticado
    # Requer autenticação JWT
    field :me, Types::UserType, null: true, description: "Retorna o perfil do usuário autenticado"
    
    def me
      # context[:current_user] foi definido no GraphqlController
      context[:current_user]
    end

    # Query: Listar todos os usuários
    # Requer autenticação JWT
    field :users, [Types::UserType], null: false, description: "Lista todos os usuários (requer autenticação)"
    
    def users
      raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
      
      User.all
    end

    # Query: Buscar um usuário por ID
    # Requer autenticação JWT
    field :user, Types::UserType, null: true, description: "Busca um usuário por ID (requer autenticação)" do
      argument :id, ID, required: true
    end
    
    def user(id:)
      raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
      
      User.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Usuário não encontrado"
    end

    # TODO: remove me
    field :test_field, String, null: false,
      description: "An example field added by the generator"
    def test_field
      "Hello World!"
    end
  end
end
