# Página de destino do link de confirmação. Confirmar muda dados, então quem faz isso é um
# POST disparado pelo JavaScript da página, não o GET (que um antivírus ou o pré-visualizador
# do e-mail abriria sozinho, "confirmando" sem a pessoa).
class EmailConfirmationsController < ApplicationController
  def show
    render layout: false
  end
end
