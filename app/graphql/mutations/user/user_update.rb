class Mutations::User::UserUpdate < GraphQL::Schema::Mutation
  argument :id, ID, required: true
  argument :email, String, required: false
  argument :password, String, required: false

  field :user, Types::UserType, null: true
  field :errors, [String], null: false

  def resolve(id:, **attributes)
    raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
    
    # Autorização por dono: ninguém altera a conta de outro usuário.
    raise GraphQL::ExecutionError, "Você não tem permissão para alterar este usuário" unless id.to_s == context[:current_user].id.to_s

    user = context[:current_user]
    if user.update(attributes.compact)
      { user: user, errors: [] }
    else
      { user: nil, errors: user.errors.full_messages }
    end
  end
end