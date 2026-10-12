class Mutations::User::UserDelete < GraphQL::Schema::Mutation
  argument :id, ID, required: true

  field :user, Types::UserType, null: true
  field :errors, [ String ], null: false

  def resolve(id:)
    raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]

    # Autorização por dono: ninguém exclui a conta de outro usuário.
    raise GraphQL::ExecutionError, "Você não tem permissão para excluir este usuário" unless id.to_s == context[:current_user].id.to_s

    user = context[:current_user]
    if user.destroy
      { user: user, errors: [] }
    else
      { user: nil, errors: user.errors.full_messages }
    end
  end
end
