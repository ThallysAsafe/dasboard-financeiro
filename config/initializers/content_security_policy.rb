# Política de segurança de conteúdo. JS e CSS das páginas são arquivos servidos
# pelo próprio app ('self'). O único script inline é o do importmap, liberado por
# nonce (um valor por resposta): um script injetado não tem o nonce e não executa.
# Nem <style>, nem atributos style="...", nem handlers inline (onclick=...) são
# permitidos: a página usa classes CSS e addEventListener. Mostrar/esconder via
# element.style.display (CSSOM) continua valendo, a CSP não o bloqueia.
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
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end

# O GraphiQL (só em desenvolvimento) carrega scripts de CDN e usa inline; fora
# da política das páginas do app.
if Rails.env.development?
  Rails.application.config.to_prepare do
    GraphiQL::Rails::EditorsController.content_security_policy false
  end
end
