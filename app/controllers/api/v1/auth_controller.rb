# frozen_string_literal: true

module Api
  module V1
    # Controller de autenticação
    # Responsável por login, logout e informações do usuário autenticado
    class AuthController < ApplicationController
      # Pula a autenticação para login (não faz sentido pedir token para fazer login)
      skip_before_action :verify_authenticity_token
      
      # Adiciona autenticação apenas para as actions que precisam
      include Authenticable
      skip_before_action :authenticate_request!, only: [:login]

      # POST /api/v1/auth/login
      # Faz login e retorna um token JWT
      # 
      # Corpo da requisição:
      # {
      #   "email": "usuario@exemplo.com",
      #   "password": "senha123"
      # }
      # 
      # Resposta de sucesso (200):
      # {
      #   "token": "eyJhbGciOiJIUzI1NiJ9...",
      #   "user": {
      #     "id": 1,
      #     "email": "usuario@exemplo.com"
      #   }
      # }
      def login
        user = User.find_by(email: params[:email])

        # Valida se o usuário existe e a senha está correta
        if user&.authenticate(params[:password])
          # Gera o token JWT com o ID do usuário
          token = JsonWebToken.encode(user_id: user.id)
          
          render json: {
            token: token,
            user: {
              id: user.id,
              email: user.email
            }
          }, status: :ok
        else
          render json: { error: 'Email ou senha inválidos' }, status: :unauthorized
        end
      end

      # GET /api/v1/auth/me
      # Retorna informações do usuário autenticado
      # Requer token JWT no header: Authorization: Bearer <token>
      # 
      # Resposta de sucesso (200):
      # {
      #   "user": {
      #     "id": 1,
      #     "email": "usuario@exemplo.com"
      #   }
      # }
      def me
        render json: {
          user: {
            id: current_user.id,
            email: current_user.email
          }
        }, status: :ok
      end

      # POST /api/v1/auth/logout
      # Logout (stateless - apenas retorna sucesso)
      # O cliente deve descartar o token localmente
      # 
      # Resposta de sucesso (200):
      # {
      #   "message": "Logout realizado com sucesso"
      # }
      def logout
        # JWT é stateless, então o logout é feito no cliente
        # O servidor apenas confirma a operação
        render json: { message: 'Logout realizado com sucesso' }, status: :ok
      end
    end
  end
end
