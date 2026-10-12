require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    config.active_record.query_log_tags_enabled = true
    config.active_record.query_log_tags = [
      # Rails query log tags:
      :application, :controller, :action, :job,
      # GraphQL-Ruby query log tags:
      current_graphql_operation: -> { GraphQL::Current.operation_name },
      current_graphql_field: -> { GraphQL::Current.field&.path },
      current_dataloader_source: -> { GraphQL::Current.dataloader_source_class }
    ]
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Rate limiting de autenticação (config/initializers/rack_attack.rb)
    config.middleware.use Rack::Attack

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # O app é usado no Brasil: "hoje" precisa ser o dia de Brasília. Em UTC, depois
    # das 21h o servidor já estaria no dia seguinte e geraria recorrências futuras.
    config.time_zone = "Brasilia"
    config.i18n.default_locale = :"pt-BR"
    # config.eager_load_paths << Rails.root.join("extras")

    # Jobs e agendamento com GoodJob (fila no próprio Postgres). O modo async roda
    # o executor e o scheduler de cron dentro do processo web, sem worker extra.
    # O cron é fixado no fuso de Brasília: o dia do mês das recorrências é o dia
    # local, e o job é idempotente, então uma execução perdida (app fora do ar à
    # meia-noite) é recuperada pela seguinte.
    config.active_job.queue_adapter = :good_job
    config.good_job.execution_mode = :async
    config.good_job.max_threads = 2 # o pool do banco é pequeno e compartilhado com o Puma
    config.good_job.enable_cron = !Rails.env.test?
    config.good_job.cron = {
      sync_recurring_entries: {
        cron: "5 0 * * * America/Sao_Paulo",
        class: "SyncRecurringEntriesJob",
        description: "Gera os lançamentos recorrentes devidos de todos os usuários"
      }
    }
  end
end
