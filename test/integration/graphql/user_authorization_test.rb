require "test_helper"

# Um usuário autenticado não pode ler, alterar nem excluir a conta de outro.
class UserAuthorizationGraphqlTest < ActiveSupport::TestCase
  def execute(query, variables: {}, user: users(:one))
    AppSchema.execute(query, variables: variables, context: { current_user: user }).to_h
  end

  UPDATE = <<~GRAPHQL
    mutation($id: ID!, $email: String, $password: String) {
      userUpdate(id: $id, email: $email, password: $password) { user { id email } errors }
    }
  GRAPHQL

  DELETE = <<~GRAPHQL
    mutation($id: ID!) { userDelete(id: $id) { user { id } errors } }
  GRAPHQL

  USER = "query($id: ID!) { user(id: $id) { id email } }"

  test "userUpdate em outro usuário é negado e não altera nada" do
    other = users(:two)
    result = execute(UPDATE, variables: { "id" => other.id.to_s, "email" => "invasor@exemplo.com", "password" => "invasor123" })

    assert_match(/permissão/, result["errors"].first["message"])
    assert_equal "dois@exemplo.com", other.reload.email
    assert other.authenticate("123456")
  end

  test "userUpdate na própria conta funciona" do
    me = users(:one)
    result = execute(UPDATE, variables: { "id" => me.id.to_s, "email" => "novo@exemplo.com" })

    assert_nil result["errors"]
    assert_equal "novo@exemplo.com", me.reload.email
  end

  test "userDelete em outro usuário é negado e preserva a conta e os dados" do
    other = users(:two)
    other.transactions.create!(kind: :income, description: "Salário", amount: 10, date: Date.new(2026, 8, 1))

    assert_no_difference [ "User.count", "Wallet.count", "Transaction.count" ] do
      result = execute(DELETE, variables: { "id" => other.id.to_s })
      assert_match(/permissão/, result["errors"].first["message"])
    end
  end

  test "userDelete na própria conta funciona" do
    me = users(:one)
    result = execute(DELETE, variables: { "id" => me.id.to_s })

    assert_nil result["errors"]
    assert_not User.exists?(me.id)
  end

  test "mutations de usuário exigem autenticação" do
    other = users(:two)
    [ [ UPDATE, { "id" => other.id.to_s, "email" => "x@x.com" } ], [ DELETE, { "id" => other.id.to_s } ] ].each do |query, vars|
      result = execute(query, variables: vars, user: nil)
      assert_match(/autenticado/, result["errors"].first["message"])
    end
    assert User.exists?(other.id)
  end

  test "user(id) só devolve o próprio usuário" do
    me = users(:one)
    other = users(:two)

    assert_equal me.email, execute(USER, variables: { "id" => me.id.to_s }).dig("data", "user", "email")

    result = execute(USER, variables: { "id" => other.id.to_s })
    assert_nil result.dig("data", "user")
    assert_match(/não encontrado/, result["errors"].first["message"])
  end

  test "a query users não existe mais" do
    result = execute("{ users { email } }")

    assert_match(/doesn't exist/, result["errors"].first["message"])
  end

  test "me continua funcionando" do
    assert_equal "um@exemplo.com", execute("{ me { email } }").dig("data", "me", "email")
  end
end
