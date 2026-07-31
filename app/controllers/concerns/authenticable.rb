# frozen_string_literal: true

# Concern para autenticação em controllers
# Adicione `include Authenticable` em controllers que precisam de autenticação
module Authenticable
  extend ActiveSupport::Concern

  included do
    # Método executado antes de cada action
    before_action :authenticate_request!
    
    # Disponibiliza @current_user para os controllers
    attr_reader :current_user
  end

  private

  # Valida o token JWT e define o usuário atual
  # Se o token for inválido, retorna erro 401 (Unauthorized)
  def authenticate_request!
    @current_user = find_user_from_token
    
    render_unauthorized unless @current_user
  end

  # Extrai o token do header Authorization
  # Formato esperado: "Authorization: Bearer <token>"
  # @return [String, nil] Token JWT ou nil
  def token_from_request_headers
    request.headers['Authorization']&.split(' ')&.last
  end

  # Busca o usuário a partir do token JWT
  # @return [User, nil] Usuário autenticado ou nil
  def find_user_from_token
    token = token_from_request_headers
    return nil unless token

    # Decodifica o token
    decoded_token = JsonWebToken.decode(token)
    return nil unless decoded_token

    # Busca o usuário pelo ID armazenado no token
    User.find_by(id: decoded_token[:user_id])
  rescue ActiveRecord::RecordNotFound
    nil
  end

  # Retorna erro 401 (Não autorizado)
  def render_unauthorized
    render json: { error: 'Unauthorized - Token inválido ou ausente' }, status: :unauthorized
  end
end
