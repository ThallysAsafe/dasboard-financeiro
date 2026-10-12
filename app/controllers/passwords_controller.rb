# Páginas de recuperação de senha. O formulário chama a API REST; o token só é lido no
# navegador (query string) e enviado por POST, nunca é processado num GET.
class PasswordsController < ApplicationController
  def forgot
    render layout: false
  end

  def reset
    render layout: false
  end
end
