# Política de segurança de conteúdo. As páginas são documentos autocontidos com
# <script> e <style> inline, liberados apenas por nonce (um valor por resposta):
# um script injetado não tem o nonce e não executa. Handlers inline
# (onclick=...) não são permitidos; a página usa addEventListener.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.object_src :none
    policy.manifest_src :self
    policy.connect_src :self
    policy.img_src :self, :data
    policy.script_src :self
    # Google Fonts (a única origem externa usada pelas páginas).
    policy.style_src :self, "https://fonts.googleapis.com"
    policy.font_src :self, "https://fonts.gstatic.com"
    # Atributos style="..." são só estilo; scripts continuam sob nonce.
    policy.style_src_attr :unsafe_inline
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end

# O GraphiQL (só em desenvolvimento) carrega scripts de CDN e usa inline; fora
# da política das páginas do app.
if Rails.env.development?
  Rails.application.config.to_prepare do
    GraphiQL::Rails::EditorsController.content_security_policy false
  end
end
