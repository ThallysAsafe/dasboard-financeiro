# frozen_string_literal: true

# Concern para autenticação em controllers
# Adicione `include Authenticable` em controllers que precisam de autenticação
module Authenticable
  extend ActiveSupport::Concern
  include TokenAuthentication

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

  # Retorna erro 401 (Não autorizado)
  def render_unauthorized
    render json: { error: "Unauthorized - Token inválido ou ausente" }, status: :unauthorized
  end
end
