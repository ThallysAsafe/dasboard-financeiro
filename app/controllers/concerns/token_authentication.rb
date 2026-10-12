# frozen_string_literal: true

# Como o JWT chega ao servidor e como é entregue ao navegador.
#
# - Clientes de API mandam `Authorization: Bearer <token>`.
# - O navegador usa um cookie HttpOnly: o JS da página nunca enxerga o token,
#   então um XSS não consegue roubá-lo.
#
# Como cookies são enviados automaticamente pelo navegador, aceitá-los sem
# cuidado abriria CSRF. Por isso o cookie só vale em requisições que levam o
# cabeçalho X-Requested-With: um site de terceiros não consegue enviá-lo sem
# passar por preflight de CORS (que este app não libera). SameSite=Strict é a
# segunda camada.
module TokenAuthentication
  extend ActiveSupport::Concern

  COOKIE_NAME = :auth_token
  AJAX_HEADER = "X-Requested-With"
  AJAX_VALUE = "XMLHttpRequest"

  private

  def authentication_token
    bearer_token || cookie_token
  end

  def bearer_token
    request.headers["Authorization"]&.split(" ")&.last
  end

  def cookie_token
    cookies[COOKIE_NAME] if request.headers[AJAX_HEADER] == AJAX_VALUE
  end

  # Usuário de uma requisição de API (Bearer, ou cookie + cabeçalho).
  def find_user_from_token
    JsonWebToken.user_for(authentication_token)
  end

  # Usuário para navegação de página (GET de HTML), que não leva cabeçalho
  # customizado. Só lê; nenhuma ação que altere dados usa este caminho.
  def find_user_from_cookie
    JsonWebToken.user_for(cookies[COOKIE_NAME])
  end

  def set_auth_cookie(user)
    cookies[COOKIE_NAME] = {
      value: JsonWebToken.issue_for(user),
      httponly: true,
      same_site: :strict,
      secure: request.ssl?,
      expires: JsonWebToken::TTL.from_now
    }
  end

  def clear_auth_cookie
    cookies.delete(COOKIE_NAME)
  end
end
