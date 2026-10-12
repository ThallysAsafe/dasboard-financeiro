require "test_helper"

class WalletGraphqlTest < ActiveSupport::TestCase
  def execute(query, variables: {}, user: users(:one))
    AppSchema.execute(query, variables: variables, context: { current_user: user }).to_h
  end

  test "wallet devolve a carteira do próprio usuário" do
    users(:one).wallet.update!(name: "Nubank", initial_balance: 250)
    wallet = execute("{ wallet { name initialBalance balance } }").dig("data", "wallet")

    assert_equal "Nubank", wallet["name"]
    assert_equal 250.0, wallet["initialBalance"]
  end

  test "wallet exige autenticação" do
    result = execute("{ wallet { name } }", user: nil)

    assert_equal "Você precisa estar autenticado", result["errors"].first["message"]
  end

  test "walletUpdate edita nome e saldo inicial da própria carteira, só dela" do
    result = execute('mutation { walletUpdate(name: "Itaú", initialBalance: 500) { wallet { name initialBalance } errors } }')
                .dig("data", "walletUpdate")

    assert_empty result["errors"]
    assert_equal "Itaú", users(:one).wallet.reload.name
    assert_equal 500, users(:one).wallet.initial_balance
    assert_not_equal "Itaú", users(:two).wallet.reload.name
  end

  test "walletUpdate recusa nome vazio em errors" do
    result = execute('mutation { walletUpdate(name: "") { wallet { name } errors } }').dig("data", "walletUpdate")

    assert_nil result["wallet"]
    assert_not_empty result["errors"]
    assert_not_equal "", users(:one).wallet.reload.name
  end

  test "walletUpdate exige autenticação" do
    result = execute('mutation { walletUpdate(name: "X") { errors } }', user: nil)

    assert_equal "Você precisa estar autenticado", result["errors"].first["message"]
  end

  test "não existe mais criar, apagar nem listar carteiras" do
    [ 'mutation { walletCreate(name: "X") { errors } }',
      'mutation { walletDelete(id: "1") { errors } }',
      "{ wallets { id } }" ].each do |query|
      assert execute(query)["errors"].present?, query
    end
    assert_equal 2, Wallet.count
  end

  test "userCreate pelo GraphQL já cria a carteira" do
    result = execute('mutation { userCreate(email: "novo@exemplo.com", password: "senhaforte123") { user { id } errors } }', user: nil)

    assert_empty result.dig("data", "userCreate", "errors")
    assert_equal 1, Wallet.joins(:user).where(users: { email: "novo@exemplo.com" }).count
  end
end
