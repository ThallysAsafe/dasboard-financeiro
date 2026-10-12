class DashboardController < ApplicationController
  include TokenAuthentication

  # A página só é entregue a quem tem sessão válida: sem isso o HTML do painel
  # aparecia por um instante antes do JS redirecionar para o login.
  before_action :require_login

  # A view é um documento HTML completo (como sessions#new), então o layout
  # padrão só a aninharia dentro de outro <html>.
  def index
    render layout: false
  end

  private

  def require_login
    redirect_to "/login" unless find_user_from_cookie
  end
end
