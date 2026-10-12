# Limites de tentativas de autenticação, compartilhados entre o Rack::Attack
# (rota REST de login) e as mutations GraphQL, que chegam todas em POST /graphql
# e por isso não podem ser distinguidas por caminho.
#
# Os contadores ficam em Rack::Attack.cache, então REST e GraphQL somam no
# mesmo balde.
module AuthThrottle
  # regra => [máximo de tentativas, janela]
  LIMITS = {
    "login/ip" => [ 5, 1.minute ],
    "login/email" => [ 5, 1.minute ],
    "signup/ip" => [ 5, 1.hour ],
    # e-mails: evitam usar o app para entupir a caixa de alguém ou adivinhar tokens
    "password-forgot/ip" => [ 5, 1.hour ],
    "password-forgot/email" => [ 3, 1.hour ],
    "password-reset/ip" => [ 10, 1.hour ],
    "email-confirm/ip" => [ 20, 1.hour ],
    "email-resend/ip" => [ 5, 1.hour ]
  }.freeze

  MESSAGE = "Muitas tentativas. Tente novamente em instantes.".freeze

  # Registra uma tentativa e informa se o limite da regra foi ultrapassado.
  # Sem chave (ex.: IP desconhecido) não há o que limitar.
  def self.exceeded?(rule, key)
    return false if key.blank?

    limit, period = LIMITS.fetch(rule)
    Rack::Attack.cache.count("#{rule}:#{normalize(key)}", period) > limit
  end

  def self.normalize(key)
    key.to_s.downcase.strip
  end
end
