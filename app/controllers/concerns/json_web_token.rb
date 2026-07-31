# frozen_string_literal: true

# Concern para gerenciar tokens JWT
# Responsável por codificar e decodificar tokens
module JsonWebToken
  extend ActiveSupport::Concern

  # Chave secreta para assinar o token
  # Em produção, use ENV['SECRET_KEY_BASE'] ou Rails.application.secret_key_base
  SECRET_KEY = Rails.application.secret_key_base

  # Codifica (gera) um token JWT
  # @param payload [Hash] Dados que serão armazenados no token (ex: { user_id: 1 })
  # @param exp [Integer] Tempo de expiração em horas (padrão: 24h)
  # @return [String] Token JWT codificado
  def self.encode(payload, exp = 24.hours.from_now)
    # Adiciona tempo de expiração ao payload
    payload[:exp] = exp.to_i
    
    # Codifica o token usando a chave secreta
    JWT.encode(payload, SECRET_KEY)
  end

  # Decodifica (valida) um token JWT
  # @param token [String] Token JWT a ser decodificado
  # @return [HashWithIndifferentAccess, nil] Payload do token ou nil se inválido
  def self.decode(token)
    # Decodifica o token e retorna o payload
    decoded = JWT.decode(token, SECRET_KEY)[0]
    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError => e
    # Retorna nil se o token for inválido ou expirado
    Rails.logger.error "JWT Decode Error: #{e.message}"
    nil
  end
end
