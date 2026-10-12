require "test_helper"

# Recuperar senha e confirmar e-mail pela API REST.
class EmailFlowsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  AJAX = { "X-Requested-With" => "XMLHttpRequest" }.freeze

  # A janela do throttle é fixa (alinhada ao relógio): congelar evita cruzar a virada da hora.
  setup do
    Rack::Attack.cache.store.clear
    travel_to Time.current.beginning_of_day + 10.hours + 5.seconds
  end

  teardown { Rack::Attack.cache.store.clear }

  def forgot(email, ip: "10.2.0.1")
    post "/api/v1/auth/password/forgot", params: { email: email }, headers: { "REMOTE_ADDR" => ip }
  end

  def reset(token, password: "novasenha1234", confirmation: password, ip: "10.2.0.1")
    post "/api/v1/auth/password/reset",
         params: { token: token, password: password, password_confirmation: confirmation },
         headers: { "REMOTE_ADDR" => ip }
  end

  def confirm(token, ip: "10.2.0.1")
    post "/api/v1/auth/email/confirm", params: { token: token }, headers: { "REMOTE_ADDR" => ip }
  end

  def token_do_ultimo_email
    link = ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{https?://\S+}]
    Rack::Utils.parse_query(URI.parse(link).query)["token"]
  end

  def login_cookie(email: "um@exemplo.com", password: "123456")
    post "/api/v1/auth/login", params: { email: email, password: password }
  end

  # --- esqueci a senha

  test "a resposta é a mesma para uma conta que existe e para uma que não existe" do
    forgot("um@exemplo.com")
    existente = [ response.status, response.body ]
    forgot("ninguem@exemplo.com")
    inexistente = [ response.status, response.body ]

    assert_equal 200, existente.first
    assert_equal existente, inexistente, "não pode revelar quem está cadastrado"
  end

  test "só envia o e-mail quando a conta existe" do
    assert_enqueued_emails 1 do
      forgot("um@exemplo.com")
    end
    assert_no_enqueued_emails do
      forgot("ninguem@exemplo.com")
    end
  end

  test "o e-mail é normalizado: maiúsculas e espaços encontram a conta" do
    assert_enqueued_emails 1 do
      forgot("  UM@Exemplo.COM ")
    end
  end

  test "e-mail em branco ou ausente também responde igual e não envia nada" do
    assert_no_enqueued_emails do
      forgot("")
      assert_response :ok
      post "/api/v1/auth/password/forgot"
      assert_response :ok
    end
  end

  test "o e-mail entregue tem o link e o token funciona" do
    perform_enqueued_jobs { forgot("um@exemplo.com") }

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "um@exemplo.com" ], mail.to
    assert_equal users(:one), User.find_by_token_for(:password_reset, token_do_ultimo_email)
  end

  test "o 6º pedido do mesmo IP na hora recebe 429" do
    5.times { |i| forgot("pessoa#{i}@exemplo.com") ; assert_response :ok }

    assert_no_enqueued_emails do
      forgot("um@exemplo.com")
    end
    assert_response :too_many_requests
  end

  test "o mesmo e-mail não pode ser bombardeado nem usando IPs diferentes" do
    3.times { |i| forgot("um@exemplo.com", ip: "10.2.1.#{i}"); assert_response :ok }

    forgot("um@exemplo.com", ip: "10.2.1.99")
    assert_response :too_many_requests
  end

  # --- redefinir a senha

  test "redefine a senha: a nova funciona, a antiga não, e o token vale uma vez só" do
    perform_enqueued_jobs { forgot("um@exemplo.com") }
    token = token_do_ultimo_email

    reset(token, password: "novasenha1234")
    assert_response :ok
    assert User.authenticate_with("um@exemplo.com", "novasenha1234")
    assert_nil User.authenticate_with("um@exemplo.com", "123456")

    reset(token, password: "outrasenha9999")
    assert_response :unprocessable_entity
    assert User.authenticate_with("um@exemplo.com", "novasenha1234"), "a segunda tentativa não pode trocar de novo"
  end

  test "redefinir derruba as sessões abertas" do
    token_antigo = JsonWebToken.issue_for(users(:one))
    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{token_antigo}" }
    assert_response :ok

    reset(User.find(users(:one).id).generate_token_for(:password_reset))

    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{token_antigo}" }
    assert_response :unauthorized
  end

  test "redefinir não abre a sessão sozinho" do
    reset(users(:one).generate_token_for(:password_reset))

    assert_response :ok
    assert_nil response.headers["Set-Cookie"]
  end

  test "link inválido, adulterado, ausente ou de outra finalidade volta 422 sem trocar nada" do
    [ "lixo", "", nil, users(:one).generate_token_for(:email_confirmation) ].each do |token|
      reset(token)

      assert_response :unprocessable_entity, token.inspect
      assert_match(/inválido ou expirado/, response.parsed_body["error"])
    end
    assert User.authenticate_with("um@exemplo.com", "123456")
  end

  test "link expirado (30 minutos)" do
    token = users(:one).generate_token_for(:password_reset)

    travel 31.minutes do
      reset(token)
      assert_response :unprocessable_entity
    end
    assert User.authenticate_with("um@exemplo.com", "123456")
  end

  test "senhas diferentes: erro, a senha não muda e o token continua valendo para tentar de novo" do
    token = User.find(users(:one).id).generate_token_for(:password_reset)

    reset(token, password: "novasenha1234", confirmation: "diferente12345")
    assert_response :unprocessable_entity
    assert_match(/Confirmação da senha/, response.parsed_body["errors"].join)
    assert User.authenticate_with("um@exemplo.com", "123456")

    reset(token, password: "novasenha1234")
    assert_response :ok
  end

  test "senha curta, em branco ou igual ao e-mail é recusada, em português" do
    token = User.find(users(:one).id).generate_token_for(:password_reset)

    { "curta12" => /muito curto/, "" => /não pode ficar em branco/, "um@exemplo.com" => /igual ao e-mail/ }.each do |senha, mensagem|
      reset(token, password: senha)

      assert_response :unprocessable_entity, senha.inspect
      assert_match(mensagem, response.parsed_body["errors"].join, senha.inspect)
    end
    assert User.authenticate_with("um@exemplo.com", "123456"), "nenhuma tentativa inválida troca a senha"
  end

  test "o 11º pedido de redefinição do mesmo IP na hora recebe 429" do
    10.times { reset("lixo"); assert_response :unprocessable_entity }

    reset("lixo")
    assert_response :too_many_requests
  end

  # --- confirmar o e-mail

  test "confirmar com o link do e-mail marca a conta como confirmada" do
    users(:one).update_columns(email_confirmed_at: nil)
    perform_enqueued_jobs { UserMailer.email_confirmation(users(:one)).deliver_later }

    confirm(token_do_ultimo_email)

    assert_response :ok
    assert users(:one).reload.email_confirmed?
    assert_nil response.headers["Set-Cookie"]
  end

  test "confirmar duas vezes é inofensivo" do
    token = users(:one).generate_token_for(:email_confirmation)

    confirm(token)
    primeira = users(:one).reload.email_confirmed_at
    confirm(token)

    assert_response :ok
    assert_equal primeira.to_i, users(:one).reload.email_confirmed_at.to_i
  end

  test "link inválido, de outra finalidade ou expirado (3 dias) não confirma" do
    expirado = users(:one).generate_token_for(:email_confirmation)

    [ "lixo", "", users(:one).generate_token_for(:password_reset) ].each do |token|
      confirm(token)
      assert_response :unprocessable_entity, token.inspect
    end
    travel 4.days do
      confirm(expirado)
      assert_response :unprocessable_entity
    end
    assert_not users(:one).reload.email_confirmed?
  end

  test "o link de confirmação antigo deixa de valer depois de trocar o e-mail" do
    user = User.find(users(:one).id)
    token = user.generate_token_for(:email_confirmation)
    user.update!(email: "trocado@exemplo.com")

    confirm(token)

    assert_response :unprocessable_entity
    assert_not user.reload.email_confirmed?
  end

  # --- reenviar a confirmação

  test "reenviar exige estar logado" do
    post "/api/v1/auth/email/resend", headers: AJAX

    assert_response :unauthorized
  end

  test "reenviar manda o e-mail para quem ainda não confirmou" do
    login_cookie

    assert_enqueued_emails 1 do
      post "/api/v1/auth/email/resend", headers: AJAX
    end
    assert_response :ok
    assert_match(/um@exemplo\.com/, response.parsed_body["message"])
  end

  test "reenviar não manda nada para quem já confirmou" do
    users(:one).confirm_email!
    login_cookie

    assert_no_enqueued_emails do
      post "/api/v1/auth/email/resend", headers: AJAX
    end
    assert_match(/já está confirmado/, response.parsed_body["message"])
  end

  test "reenviar tem limite por IP" do
    login_cookie
    5.times { post "/api/v1/auth/email/resend", headers: AJAX; assert_response :ok }

    post "/api/v1/auth/email/resend", headers: AJAX
    assert_response :too_many_requests
  end

  # --- o estado aparece no painel

  test "/me informa se o e-mail está confirmado" do
    login_cookie
    get "/api/v1/auth/me", headers: AJAX
    assert_equal false, response.parsed_body.dig("user", "email_confirmed")

    users(:one).confirm_email!
    get "/api/v1/auth/me", headers: AJAX
    assert_equal true, response.parsed_body.dig("user", "email_confirmed")
  end

  test "o GraphQL também expõe emailConfirmed" do
    users(:one).confirm_email!
    token = JsonWebToken.issue_for(users(:one))

    post "/graphql", params: { query: "{ me { emailConfirmed } }" },
                     headers: { "Authorization" => "Bearer #{token}" }, as: :json

    assert_equal true, response.parsed_body.dig("data", "me", "emailConfirmed")
  end

  # --- cadastro

  test "cadastrar envia o e-mail de confirmação" do
    assert_enqueued_emails 1 do
      post "/api/v1/auth/signup", params: { email: "novo@exemplo.com", password: "senhaforte123",
                                            password_confirmation: "senhaforte123" }
    end
    assert_response :created
    assert_not User.find_by(email: "novo@exemplo.com").email_confirmed?
  end
end
