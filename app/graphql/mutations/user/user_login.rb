# frozen_string_literal: true

module Mutations
  module User
    class UserLogin < GraphQL::Schema::Mutation
      argument :email, String, required: true
      argument :password, String, required: true

      field :token, String, null: true
      field :user, Types::UserType, null: true
      field :errors, [String], null: false

      def resolve(email:, password:)
        user = ::User.find_by(email: email)

        if user&.authenticate(password)
          token = JsonWebToken.encode(user_id: user.id)
          { token: token, user: user, errors: [] }
        else
          { token: nil, user: nil, errors: ["Email ou senha inválidos"] }
        end
      end
    end
  end
end
