# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    # Mutations de Usuário (requerem autenticação JWT)
    field :user_create, mutation: Mutations::User::UserCreate
    field :user_update, mutation: Mutations::User::UserUpdate
    field :user_delete, mutation: Mutations::User::UserDelete
    
    # TODO: remove me
    field :test_field, String, null: false,
      description: "An example field added by the generator"
    def test_field
      "Hello World"
    end
  end
end
