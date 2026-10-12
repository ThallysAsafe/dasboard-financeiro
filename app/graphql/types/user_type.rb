# frozen_string_literal: true

module Types
  class UserType < GraphQL::Schema::Object
    field :id, ID, null: false
    field :email, String, null: false
    field :email_confirmed, Boolean, null: false, description: "Se o e-mail já foi confirmado pelo link enviado"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    # NUNCA exponha a senha, nem o hash!

    def email_confirmed
      object.email_confirmed?
    end
  end
end
