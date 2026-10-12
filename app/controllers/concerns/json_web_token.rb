# frozen_string_literal: true

# Concern para gerenciar tokens JWT
# Responsável por codificar e decodificar tokens
module JsonWebToken
  extend ActiveSupport::Concern

  # Chave secreta para assinar o token
  # Em produção, use ENV['SECRET_KEY_BASE'] ou Rails.application.secret_key_base
  SECRET_KEY = Rails.application.secret_key_base

  # Fixa o algoritmo na verificação: o token não escolhe como será validado.
  ALGORITHM = "HS256"

  # Validade do token (e do cookie que o carrega).
  TTL = 24.hours

  # Codifica (gera) um token JWT
  # @param payload [Hash] Dados que serão armazenados no token (ex: { user_id: 1 })
  # @param exp [Integer] Tempo de expiração em horas (padrão: 24h)
  # @return [String] Token JWT codificado
  def self.encode(payload, exp = TTL.from_now)
    # Adiciona tempo de expiração ao payload
    payload[:exp] = exp.to_i

    # Codifica o token usando a chave secreta
    JWT.encode(payload, SECRET_KEY, ALGORITHM)
  end

  # Emite o token de um usuário já carregando a versão vigente dele. Quando
  # `token_version` é incrementado, todos os tokens anteriores deixam de valer.
  def self.issue_for(user)
    encode(user_id: user.id, tv: user.token_version)
  end

  # Resolve o usuário dono de um token válido e ainda vigente, ou nil.
  # Único ponto de autenticação por token: REST e GraphQL passam por aqui.
  def self.user_for(token)
    return nil if token.blank?

    payload = decode(token)
    return nil unless payload

    user = User.find_by(id: payload[:user_id])
    user if user && payload[:tv] == user.token_version
  end

  # Decodifica (valida) um token JWT
  # @param token [String] Token JWT a ser decodificado
  # @return [HashWithIndifferentAccess, nil] Payload do token ou nil se inválido
  def self.decode(token)
    # Decodifica o token e retorna o payload
    decoded = JWT.decode(token, SECRET_KEY, true, algorithm: ALGORITHM)[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError => e
    # Retorna nil se o token for inválido ou expirado
    Rails.logger.error "JWT Decode Error: #{e.message}"
    nil
  end
end
