# frozen_string_literal: true

module Api
  module V1
    # Controller de usuários (exemplo de controller protegido)
    # Todas as actions requerem autenticação JWT
    class UsersController < ApplicationController
      include Authenticable
      skip_before_action :verify_authenticity_token

      # GET /api/v1/users
      # Lista todos os usuários (requer autenticação)
      def index
        users = User.all
        render json: {
          users: users.map { |u| { id: u.id, email: u.email } }
        }, status: :ok
      end

      # GET /api/v1/users/:id
      # Mostra um usuário específico (requer autenticação)
      def show
        user = User.find(params[:id])
        render json: {
          user: {
            id: user.id,
            email: user.email
          }
        }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Usuário não encontrado' }, status: :not_found
      end

      # POST /api/v1/users
      # Cria um novo usuário (requer autenticação)
      # 
      # Corpo da requisição:
      # {
      #   "email": "novo@exemplo.com",
      #   "password": "senha123"
      # }
      def create
        user = User.new(user_params)

        if user.save
          render json: {
            user: {
              id: user.id,
              email: user.email
            }
          }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/users/:id
      # Atualiza um usuário (requer autenticação)
      def update
        user = User.find(params[:id])

        if user.update(user_params)
          render json: {
            user: {
              id: user.id,
              email: user.email
            }
          }, status: :ok
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Usuário não encontrado' }, status: :not_found
      end

      # DELETE /api/v1/users/:id
      # Remove um usuário (requer autenticação)
      def destroy
        user = User.find(params[:id])
        user.destroy

        render json: { message: 'Usuário removido com sucesso' }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Usuário não encontrado' }, status: :not_found
      end

      private

      def user_params
        params.permit(:email, :password)
      end
    end
  end
end
