require "test_helper"

class SignupTest < ActionDispatch::IntegrationTest
  AJAX = { "X-Requested-With" => "XMLHttpRequest" }.freeze
  SENHA = "senhaforte123".freeze

  # A janela do throttle é fixa (alinhada ao relógio): congelar o tempo evita que o
  # teste cruze a virada da hora e divida o contador.
  setup do
    Rack::Attack.cache.store.clear
    travel_to Time.current.beginning_of_day + 10.hours + 5.seconds
  end

  teardown { Rack::Attack.cache.store.clear }

  # signup(email: "x") ou signup({ email: "x" }, ip: "10.1.0.2")
  def signup(attrs = {}, ip: "10.1.0.1", **inline)
    params = { email: "novo@exemplo.com", password: SENHA, password_confirmation: SENHA }.merge(attrs, inline)
    post "/api/v1/auth/signup", params: params, headers: { "REMOTE_ADDR" => ip }
  end

  # --- sucesso

  test "cria o usuário, a carteira dele e já abre a sessão" do
    assert_difference [ "User.count", "Wallet.count" ], 1 do
      signup
    end

    assert_response :created
    user = User.find_by(email: "novo@exemplo.com")
    assert_equal user.email, response.parsed_body.dig("user", "email")
    assert_equal User::DEFAULT_WALLET_NAME, user.wallet.name
    assert user.authenticate(SENHA)
  end

  test "a sessão vai em cookie HttpOnly e o token nunca aparece no corpo" do
    signup

    assert_nil response.parsed_body["token"]
    assert_not_includes response.body, "eyJ"
    cookie = response.headers["Set-Cookie"]
    assert_match(/auth_token=/, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=strict/i, cookie)
  end

  test "depois de cadastrar já entra no dashboard e na API" do
    signup

    get "/api/v1/auth/me", headers: AJAX
    assert_response :ok
    assert_equal "novo@exemplo.com", response.parsed_body.dig("user", "email")

    get "/dashboard"
    assert_response :ok
  end

  test "normaliza o e-mail (maiúsculas e espaços)" do
    signup(email: "  Ana@Exemplo.COM ")

    assert_response :created
    assert User.exists?(email: "ana@exemplo.com")
  end

  test "ignora campos extras: não dá para escolher id nem versão de token" do
    signup(id: 999_999, token_version: 50, admin: true)

    user = User.find_by(email: "novo@exemplo.com")
    assert_not_equal 999_999, user.id
    assert_equal 0, user.token_version
  end

  # --- falhas (nada é criado e nenhum cookie é gravado)

  def assert_rejected(expected_message = nil)
    assert_response :unprocessable_entity
    assert_nil response.headers["Set-Cookie"]
    errors = response.parsed_body["errors"]
    assert errors.present?
    assert(errors.any? { |m| m.match?(expected_message) }, errors.inspect) if expected_message
  end

  test "e-mail já cadastrado, mesmo em outra caixa" do
    assert_no_difference "User.count" do
      signup(email: users(:one).email.upcase)
    end

    assert_rejected(/E-mail/)
  end

  test "senha curta" do
    assert_no_difference "User.count" do
      signup(password: "curta123", password_confirmation: "curta123")
    end

    assert_rejected(/Senha.*curto/)
  end

  test "senhas diferentes" do
    assert_no_difference "User.count" do
      signup(password_confirmation: "outrasenha123")
    end

    assert_rejected(/Confirmação da senha/)
  end

  test "sem confirmação de senha" do
    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: { email: "novo@exemplo.com", password: SENHA }
    end

    assert_rejected(/Confirmação da senha/)
  end

  test "e-mail inválido ou em branco" do
    [ "sem-arroba", "" ].each do |email|
      assert_no_difference "User.count" do
        signup(email: email)
      end
      assert_rejected
    end
  end

  test "senha igual ao e-mail" do
    signup(email: "usuario@exemplo.com", password: "usuario@exemplo.com", password_confirmation: "usuario@exemplo.com")

    assert_rejected(/igual ao e-mail/)
  end

  test "as mensagens saem em português" do
    signup(email: "x", password: "123", password_confirmation: "456")

    messages = response.parsed_body["errors"].join(" ")
    assert_no_match(/can't be|is invalid|too short|doesn't match|has already/, messages)
    assert_match(/E-mail/, messages)
  end

  # --- proteção contra abuso

  test "o 6º cadastro do mesmo IP na hora recebe 429" do
    5.times { |i| signup({ email: "pessoa#{i}@exemplo.com" }); assert_response :created }

    assert_no_difference "User.count" do
      signup(email: "pessoa9@exemplo.com")
    end
    assert_response :too_many_requests
  end

  test "o limite é por IP: outro IP continua podendo cadastrar" do
    5.times { |i| signup({ email: "pessoa#{i}@exemplo.com" }); assert_response :created }

    signup({ email: "outro@exemplo.com" }, ip: "10.1.0.2")
    assert_response :created
  end

  test "REST e GraphQL dividem o mesmo limite de cadastros" do
    3.times do |i|
      post "/graphql", params: { query: %(mutation { userCreate(email: "g#{i}@x.com", password: "#{SENHA}") { errors } }) }, as: :json,
                       headers: { "REMOTE_ADDR" => "10.1.0.1" }
    end
    2.times { |i| signup({ email: "r#{i}@exemplo.com" }); assert_response :created }

    signup(email: "excedeu@exemplo.com")
    assert_response :too_many_requests
  end

  # --- páginas

  test "a página de cadastro é servida a quem não está logado" do
    get "/signup"

    assert_response :ok
    assert_includes response.body, 'id="signupForm"'
    assert_includes response.body, 'href="/login"'
  end

  test "quem já está logado vai direto ao dashboard" do
    signup
    get "/signup"

    assert_redirected_to "/dashboard"
  end

  test "o login aponta para o cadastro e não tem mais link morto" do
    get "/login"

    assert_includes response.body, 'href="/signup"'
    assert_no_match(/href="#"/, response.body)
    assert_no_match(/Esqueceu/, response.body)
  end
end
