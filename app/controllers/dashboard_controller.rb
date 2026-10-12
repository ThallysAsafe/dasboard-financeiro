class DashboardController < ApplicationController
  # A view é um documento HTML completo (como sessions#new), então o layout
  # padrão só a aninharia dentro de outro <html>.
  def index
    render layout: false
  end
end
