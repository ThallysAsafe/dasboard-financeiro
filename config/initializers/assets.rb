# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w[ admin.js admin.css ]

# O GraphiQL só existe em desenvolvimento (group :development no Gemfile). Linkar
# os assets dele no manifest.js quebra o Sprockets em teste e o assets:precompile
# de produção, onde a gem não é carregada.
if Rails.env.development?
  Rails.application.config.assets.precompile += %w[graphiql/rails/application.css graphiql/rails/application.js]
end
