# frozen_string_literal: true

class GraphqlController < ApplicationController
  # Se estiver acessando de fora do domínio, nullify a session
  # Isso permite acesso externo à API e previne ataques CSRF
  skip_before_action :verify_authenticity_token

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    
    # Contexto do GraphQL com usuário autenticado via JWT
    context = {
      current_user: current_user,
    }
    
    result = AppSchema.execute(query, variables: variables, context: context, operation_name: operation_name)
    render json: result
  rescue StandardError => e
    raise e unless Rails.env.development?
    handle_error_in_development(e)
  end

  private

  # Retorna o usuário autenticado a partir do token JWT
  # Se não houver token ou for inválido, retorna nil (GraphQL permitirá queries públicas)
  def current_user
    @current_user ||= find_user_from_token
  end

  # Extrai o token do header Authorization
  # Formato esperado: "Authorization: Bearer <token>"
  def token_from_request_headers
    request.headers['Authorization']&.split(' ')&.last
  end

  # Busca o usuário a partir do token JWT
  def find_user_from_token
    token = token_from_request_headers
    return nil unless token

    decoded_token = JsonWebToken.decode(token)
    return nil unless decoded_token

    User.find_by(id: decoded_token[:user_id])
  rescue ActiveRecord::RecordNotFound
    nil
  end

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      if variables_param.present?
        JSON.parse(variables_param) || {}
      else
        {}
      end
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{variables_param}"
    end
  end

  def handle_error_in_development(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")

    render json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} }, status: 500
  end
end
