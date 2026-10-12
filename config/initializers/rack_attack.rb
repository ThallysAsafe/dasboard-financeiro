# frozen_string_literal: true

# Rate limiting da API REST de login e cadastro. O login/cadastro via GraphQL é limitado
# dentro das próprias mutations (ver AuthThrottle), já que o Rack::Attack só
# enxerga o caminho e todo GraphQL é POST /graphql.
#
# Dentro de to_prepare porque AuthThrottle vive em app/ e não está carregado
# durante os initializers.
Rails.application.config.to_prepare do
  # Os contadores precisam de um cache que realmente guarde valores. Em teste o
  # Rails.cache é null_store, então usa memória própria.
  Rack::Attack.cache.store = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  login = ->(req) { req.post? && req.path == "/api/v1/auth/login" }

  Rack::Attack.throttle("login/ip", limit: AuthThrottle::LIMITS["login/ip"][0],
                                    period: AuthThrottle::LIMITS["login/ip"][1]) do |req|
    req.ip if login.call(req)
  end

  # Por e-mail: barra ataque distribuído (vários IPs) contra uma única conta.
  Rack::Attack.throttle("login/email", limit: AuthThrottle::LIMITS["login/email"][0],
                                       period: AuthThrottle::LIMITS["login/email"][1]) do |req|
    AuthThrottle.normalize(req.params["email"]).presence if login.call(req)
  end

  # Cadastro: mesmo balde do userCreate do GraphQL (AuthThrottle "signup/ip").
  Rack::Attack.throttle("signup/ip", limit: AuthThrottle::LIMITS["signup/ip"][0],
                                     period: AuthThrottle::LIMITS["signup/ip"][1]) do |req|
    req.ip if req.post? && req.path == "/api/v1/auth/signup"
  end

  # E-mails de recuperação/confirmação: por IP, e por e-mail para não entupir a caixa de
  # uma pessoa (mesmo vindo de vários IPs).
  post_to = ->(req, path) { req.post? && req.path == path }
  {
    "password-forgot/ip" => "/api/v1/auth/password/forgot",
    "password-reset/ip" => "/api/v1/auth/password/reset",
    "email-confirm/ip" => "/api/v1/auth/email/confirm",
    "email-resend/ip" => "/api/v1/auth/email/resend"
  }.each do |rule, path|
    limit, period = AuthThrottle::LIMITS.fetch(rule)
    Rack::Attack.throttle(rule, limit: limit, period: period) { |req| req.ip if post_to.call(req, path) }
  end

  limit, period = AuthThrottle::LIMITS.fetch("password-forgot/email")
  Rack::Attack.throttle("password-forgot/email", limit: limit, period: period) do |req|
    AuthThrottle.normalize(req.params["email"]).presence if post_to.call(req, "/api/v1/auth/password/forgot")
  end

  Rack::Attack.throttled_responder = lambda do |_req|
    [ 429, { "Content-Type" => "application/json" }, [ { error: AuthThrottle::MESSAGE }.to_json ] ]
  end
end
