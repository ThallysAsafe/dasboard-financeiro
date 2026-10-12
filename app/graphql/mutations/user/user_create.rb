class Mutations::User::UserCreate < GraphQL::Schema::Mutation
  argument :email, String, required: true
  argument :password, String, required: true

  field :user, Types::UserType, null: true
  field :errors, [String], null: false

  def resolve(email:, password:)
    raise GraphQL::ExecutionError, AuthThrottle::MESSAGE if AuthThrottle.exceeded?("signup/ip", context[:ip])

    user = User.new(email: email, password: password)
    if user.save
      { user: user, errors: [] }
    else
      { user: nil, errors: user.errors.full_messages }
    end
  end
end