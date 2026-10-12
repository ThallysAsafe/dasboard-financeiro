require "test_helper"

# Sessão do navegador: cookie HttpOnly, defesa contra CSRF, páginas protegidas
# no servidor e CSP sem scripts inline.
class BrowserSessionTest < ActionDispatch::IntegrationTest
  AJAX = { "X-Requested-With" => "XMLHttpRequest" }.freeze

  setup { Rack::Attack.cache.store.clear }

  def login(email = "um@exemplo.com", password = "123456")
    post "/api/v1/auth/login", params: { email: email, password: password }
  end

  def gql(query, headers: AJAX)
    post "/graphql", params: { query: query }, headers: headers, as: :json
    response.parsed_body
  end

  # --- cookie

  test "login entrega o token só em cookie HttpOnly SameSite=Strict, nunca no corpo" do
    login

    assert_response :ok
    assert_nil response.parsed_body["token"]
    assert_not_includes response.body, "eyJ" # prefixo de qualquer JWT
    cookie = response.headers["Set-Cookie"]
    assert_match(/auth_token=/, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=strict/i, cookie)
  end

  test "login com senha errada não grava cookie" do
    login("um@exemplo.com", "errada")

    assert_response :unauthorized
    assert_nil response.headers["Set-Cookie"]
  end

  test "login sem senha ou sem e-mail é 401, não erro 500" do
    post "/api/v1/auth/login", params: { email: "um@exemplo.com" }
    assert_response :unauthorized

    post "/api/v1/auth/login", params: {}
    assert_response :unauthorized
  end

  test "login GraphQL e REST respondem igual a credenciais inválidas" do
    post "/graphql", params: { query: 'mutation { userLogin(email: "um@exemplo.com", password: "errada") { token errors } }' }, as: :json
    payload = response.parsed_body.dig("data", "userLogin")

    assert_nil payload["token"]
    assert_equal [ "Email ou senha inválidos" ], payload["errors"]
  end

  test "login GraphQL válido devolve um token Bearer utilizável" do
    post "/graphql", params: { query: 'mutation { userLogin(email: "UM@exemplo.com", password: "123456") { token } }' }, as: :json
    token = response.parsed_body.dig("data", "userLogin", "token")

    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :ok
  end

  test "o cookie autentica a API quando a requisição leva X-Requested-With" do
    login

    get "/api/v1/auth/me", headers: AJAX
    assert_response :ok
    assert_equal "um@exemplo.com", gql("{ me { email } }").dig("data", "me", "email")
  end

  test "CSRF: o cookie é ignorado sem o cabeçalho X-Requested-With" do
    login

    get "/api/v1/auth/me"
    assert_response :unauthorized
    assert_nil gql("{ me { email } }", headers: {}).dig("data", "me")
  end

  test "CSRF: mutation com cookie mas sem o cabeçalho não executa" do
    login

    result = gql('mutation { transactionCreate(kind: EXPENSE, description: "Invasora", amount: 1, date: "2026-08-01") { errors } }', headers: {})

    assert_match(/autenticado/, result["errors"].first["message"])
    assert_equal 0, users(:one).transactions.where(description: "Invasora").count
  end

  test "Bearer continua funcionando para clientes de API" do
    token = JsonWebToken.issue_for(users(:one))

    get "/api/v1/auth/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :ok
  end

  test "logout revoga a sessão: o cookie antigo deixa de valer" do
    login
    stolen = cookies[:auth_token]

    post "/api/v1/auth/logout", headers: AJAX
    assert_response :ok

    cookies[:auth_token] = stolen
    get "/api/v1/auth/me", headers: AJAX
    assert_response :unauthorized
  end

  # --- páginas

  test "dashboard sem sessão redireciona para o login no servidor" do
    get "/dashboard"

    assert_redirected_to "/login"
  end

  test "dashboard com sessão é entregue" do
    login
    get "/dashboard"

    assert_response :ok
    assert_includes response.body, "Painel Principal"
  end

  test "login já autenticado vai direto para o dashboard" do
    login
    get "/login"

    assert_redirected_to "/dashboard"
  end

  test "login sem sessão mostra o formulário" do
    get "/login"

    assert_response :ok
    assert_includes response.body, 'id="loginForm"'
  end

  test "cookie de token revogado não abre o dashboard" do
    login
    users(:one).revoke_tokens!

    get "/dashboard"
    assert_redirected_to "/login"
  end

  # --- CSP

  INLINE_HANDLER = /\son(click|submit|change|input|load|error)\s*=/i

  test "a página de login não usa localStorage nem handlers inline" do
    get "/login"

    assert_response :ok
    assert_no_match(/localStorage/, response.body)
    assert_no_match(INLINE_HANDLER, response.body)
  end

  test "a página de cadastro não usa localStorage nem handlers inline" do
    get "/signup"

    assert_response :ok
    assert_no_match(/localStorage/, response.body)
    assert_no_match(INLINE_HANDLER, response.body)
  end

  test "o dashboard não usa localStorage nem handlers inline" do
    login
    get "/dashboard"

    assert_response :ok
    assert_no_match(/localStorage/, response.body)
    assert_no_match(INLINE_HANDLER, response.body)
  end

  test "CSP: scripts só com nonce, sem unsafe-inline, e o nonce bate com a página" do
    get "/login"
    csp = response.headers["Content-Security-Policy"]
    script_src = csp[/script-src [^;]+/]

    assert_match(/'nonce-/, script_src)
    assert_no_match(/unsafe-inline|unsafe-eval/, script_src)
    assert_no_match(/unsafe-inline/, csp[/style-src [^;]+/]) # style-src-attr é outra diretiva
    assert_match(/object-src 'none'/, csp)
    assert_match(/frame-ancestors 'none'/, csp)

    nonce = script_src[/'nonce-([^']+)'/, 1]
    inline_scripts = response.body.scan(%r{<script\b([^>]*)>(.*?)</script>}m)
    assert_not_empty inline_scripts
    inline_scripts.each { |attrs, _| assert_includes attrs, %(nonce="#{nonce}") }
  end

  test "as páginas não têm <style> nem JavaScript próprio inline: só arquivos servidos pelo app" do
    pages = []
    get "/login" # sem sessão: com sessão ele redireciona para o dashboard
    pages << [ "/login", response.body ]
    get "/signup"
    pages << [ "/signup", response.body ]
    login
    get "/dashboard"
    pages << [ "/dashboard", response.body ]

    pages.each do |path, body|
      assert_no_match(/<style\b/, body, path)
      body.scan(%r{<script\b[^>]*>(.*?)</script>}m).flatten.each do |inline|
        assert_no_match(/function |=>|fetch\(/, inline, "#{path}: JS próprio inline")
      end
    end
  end

  test "o CSS e o JS de cada página são servidos como assets" do
    pages = {} # página => [corpo, nome do css, nome do js]
    get "/login"
    pages["/login"] = [ response.body, "login", "login" ]
    get "/signup"
    pages["/signup"] = [ response.body, "login", "signup" ] # reaproveita o CSS do login
    login
    get "/dashboard"
    pages["/dashboard"] = [ response.body, "dashboard", "dashboard" ]

    pages.each do |path, (body, css_name, js_name)|
      css = body[%r{href="(/assets/#{css_name}-[^"]+\.css)"}, 1]
      js = body[%r{(/assets/#{js_name}-[^"]+\.js)}, 1]

      assert css, "#{path} deveria linkar #{css_name}.css"
      assert js, "#{path} deveria referenciar #{js_name}.js"
      [ css, js ].each do |asset|
        get asset
        assert_response :ok, asset
      end
    end
  end

  test "CSP: o nonce muda a cada resposta" do
    get "/login"
    first = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]
    get "/login"
    second = response.headers["Content-Security-Policy"][/'nonce-([^']+)'/, 1]

    assert_not_equal first, second
  end

  test "CSP também protege o dashboard" do
    login
    get "/dashboard"

    assert_match(/script-src 'self' 'nonce-/, response.headers["Content-Security-Policy"])
  end
end
