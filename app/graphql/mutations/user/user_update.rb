class Mutations::User::UserUpdate < GraphQL::Schema::Mutation
  argument :id, ID, required: true
  argument :email, String, required: false
  argument :password, String, required: false

  field :user, Types::UserType, null: true
  field :errors, [String], null: false

  def resolve(id:, **attributes)
    raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
    
    user = User.find(id)
    if user.update(attributes.compact)
      { user: user, errors: [] }
    else
      { user: nil, errors: user.errors.full_messages }
    end
  rescue ActiveRecord::RecordNotFound
    raise GraphQL::ExecutionError, "Usuário não encontrado"
  end
end