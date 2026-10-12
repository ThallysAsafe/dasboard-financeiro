require "test_helper"

class TokenRevocationTest < ActionDispatch::IntegrationTest
  setup { Rack::Attack.cache.store.clear }

  def bearer(token) = { "Authorization" => "Bearer #{token}" }
  def me(token) = get("/api/v1/auth/me", headers: bearer(token))
  def gql_me(token) = post("/graphql", params: { query: "{ me { email } }" }, headers: bearer(token), as: :json)

  test "token válido autentica no REST e no GraphQL" do
    token = JsonWebToken.issue_for(users(:one))

    me(token)
    assert_response :ok
    gql_me(token)
    assert_equal "um@exemplo.com", response.parsed_body.dig("data", "me", "email")
  end

  test "logout invalida o token em REST e GraphQL" do
    token = JsonWebToken.issue_for(users(:one))

    post "/api/v1/auth/logout", headers: bearer(token)
    assert_response :ok

    me(token)
    assert_response :unauthorized
    gql_me(token)
    assert_nil response.parsed_body.dig("data", "me")
  end

  test "logout derruba também os outros tokens do mesmo usuário" do
    primeiro = JsonWebToken.issue_for(users(:one))
    segundo = JsonWebToken.issue_for(users(:one))

    post "/api/v1/auth/logout", headers: bearer(primeiro)
    me(segundo)
    assert_response :unauthorized
  end

  test "logout de um usuário não afeta o token de outro" do
    um = JsonWebToken.issue_for(users(:one))
    dois = JsonWebToken.issue_for(users(:two))

    post "/api/v1/auth/logout", headers: bearer(um)
    me(dois)
    assert_response :ok
  end

  test "trocar a senha invalida os tokens antigos" do
    user = User.find(users(:one).id)
    token = JsonWebToken.issue_for(user)

    user.update!(password: "novasenha123")

    me(token)
    assert_response :unauthorized
    me(JsonWebToken.issue_for(user.reload))
    assert_response :ok
  end

  test "trocar só o e-mail não derruba a sessão" do
    user = User.find(users(:one).id)
    token = JsonWebToken.issue_for(user)

    user.update!(email: "outro@exemplo.com")

    me(token)
    assert_response :ok
  end

  test "login emite um token que funciona logo em seguida" do
    post "/api/v1/auth/login", params: { email: "um@exemplo.com", password: "123456" }
    me(response.parsed_body["token"])
    assert_response :ok
  end

  test "token sem versão (emitido antes desta mudança) é recusado" do
    me(JsonWebToken.encode(user_id: users(:one).id))
    assert_response :unauthorized
  end

  test "token expirado é recusado" do
    me(JsonWebToken.encode({ user_id: users(:one).id, tv: 0 }, 1.minute.ago))
    assert_response :unauthorized
  end

  test "token assinado com outra chave ou algoritmo none é recusado" do
    forjado = JWT.encode({ user_id: users(:one).id, tv: 0, exp: 1.hour.from_now.to_i }, "outra-chave", "HS256")
    me(forjado)
    assert_response :unauthorized

    sem_assinatura = JWT.encode({ user_id: users(:one).id, tv: 0, exp: 1.hour.from_now.to_i }, nil, "none")
    me(sem_assinatura)
    assert_response :unauthorized
  end

  test "sem token é recusado" do
    get "/api/v1/auth/me"
    assert_response :unauthorized
  end
end
