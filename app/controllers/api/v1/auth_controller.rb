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
      skip_before_action :authenticate_request!, only: [ :login, :signup, :forgot_password, :reset_password, :confirm_email ]

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

      # POST /api/v1/auth/signup
      # Cria o usuário (a carteira nasce junto) e já abre a sessão pelo cookie.
      #
      # Corpo: { "email": "...", "password": "...", "password_confirmation": "..." }
      # Sucesso (201): { "user": { "id": 1, "email": "..." } }
      # Falha (422):   { "errors": [ "E-mail já está em uso", ... ] }
      def signup
        user = User.new(
          email: params[:email],
          password: params[:password],
          # to_s: sem a confirmação o has_secure_password não a validaria
          password_confirmation: params[:password_confirmation].to_s
        )

        if user.save
          set_auth_cookie(user)
          render json: { user: { id: user.id, email: user.email } }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/auth/password/forgot
      # Pede o e-mail de redefinição. A resposta é SEMPRE a mesma, exista ou não a conta,
      # para não revelar quem está cadastrado.
      def forgot_password
        user = User.find_by(email: params[:email])
        UserMailer.password_reset(user).deliver_later if user

        render json: { message: "Se existir uma conta com este e-mail, enviamos um link para redefinir a senha." }
      end

      # POST /api/v1/auth/password/reset
      # Corpo: { "token": "...", "password": "...", "password_confirmation": "..." }
      # O token vale uma vez só: trocar a senha o invalida, e também derruba as sessões abertas.
      def reset_password
        user = User.find_by_token_for(:password_reset, params[:token].to_s)
        return render json: { error: "Link inválido ou expirado. Peça um novo." }, status: :unprocessable_entity unless user

        user.password = params[:password]
        user.password_confirmation = params[:password_confirmation].to_s
        # has_secure_password ignora uma senha vazia (não troca nada), então sem esta checagem
        # a resposta seria um sucesso falso
        user.errors.add(:password, :blank) if params[:password].blank?

        if user.errors.empty? && user.save
          render json: { message: "Senha alterada. Entre com a nova senha." }
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/auth/email/confirm — Corpo: { "token": "..." }
      def confirm_email
        user = User.find_by_token_for(:email_confirmation, params[:token].to_s)
        return render json: { error: "Link inválido ou expirado. Peça um novo no painel." }, status: :unprocessable_entity unless user

        user.confirm_email!
        render json: { message: "E-mail confirmado." }
      end

      # POST /api/v1/auth/email/resend (logado)
      def resend_confirmation
        if current_user.email_confirmed?
          render json: { message: "Este e-mail já está confirmado." }
        else
          UserMailer.email_confirmation(current_user).deliver_later
          render json: { message: "Enviamos um novo link para #{current_user.email}." }
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
            email: current_user.email,
            email_confirmed: current_user.email_confirmed?
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
