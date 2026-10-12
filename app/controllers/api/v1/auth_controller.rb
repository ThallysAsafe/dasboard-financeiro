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
      skip_before_action :authenticate_request!, only: [ :login ]

      # POST /api/v1/auth/login
      # Faz login e grava o token JWT em um cookie HttpOnly
      #
      # Corpo da requisição:
      # {
      #   "email": "usuario@exemplo.com",
      #   "password": "senha123"
      # }
      #
      # Resposta de sucesso (200): o token vai num cookie HttpOnly (o JS do
      # navegador não o enxerga) e o corpo traz só o usuário:
      # {
      #   "user": {
      #     "id": 1,
      #     "email": "usuario@exemplo.com"
      #   }
      # }
      # Clientes que não são navegador obtêm um token Bearer pela mutation
      # GraphQL `userLogin`.
      def login
        user = User.authenticate_with(params[:email], params[:password])

        if user
          set_auth_cookie(user)

          render json: {
            user: {
              id: user.id,
              email: user.email
            }
          }, status: :ok
        else
          render json: { error: "Email ou senha inválidos" }, status: :unauthorized
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
      # Logout: revoga todos os tokens emitidos para o usuário
      #
      # Resposta de sucesso (200):
      # {
      #   "message": "Logout realizado com sucesso"
      # }
      def logout
        # Invalida todos os tokens do usuário incrementando a versão que eles
        # carregam; o cliente ainda deve descartar o token localmente.
        current_user.revoke_tokens!
        clear_auth_cookie
        render json: { message: "Logout realizado com sucesso" }, status: :ok
      end
    end
  end
end
