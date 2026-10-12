# frozen_string_literal: true

module Mutations
  module User
    class UserLogin < GraphQL::Schema::Mutation
      argument :email, String, required: true
      argument :password, String, required: true

      field :token, String, null: true
      field :user, Types::UserType, null: true
      field :errors, [ String ], null: false

      def resolve(email:, password:)
        if AuthThrottle.exceeded?("login/ip", context[:ip]) || AuthThrottle.exceeded?("login/email", email)
          raise GraphQL::ExecutionError, AuthThrottle::MESSAGE
        end

        user = ::User.find_by(email: email)

        if user&.authenticate(password)
          token = JsonWebToken.issue_for(user)
          { token: token, user: user, errors: [] }
        else
          { token: nil, user: nil, errors: [ "Email ou senha inválidos" ] }
        end
      end
    end
  end
end
