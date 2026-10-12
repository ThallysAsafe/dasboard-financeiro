# Materializa os lançamentos recorrentes devidos de todos os usuários.
#
# Sem isto a geração só acontece quando alguém abre o dashboard, e os saldos
# ficam defasados (e invisíveis para qualquer outro consumidor da API) até lá.
# É idempotente (marca d'água + índice único), então rodar a mais não duplica.
#
# Agende uma vez por dia (ver README): `bin/rails recurring:sync`.
class SyncRecurringEntriesJob < ApplicationJob
  queue_as :default

  def perform
    total = 0

    User.find_each do |user|
      total += user.sync_recurring_entries!
    rescue StandardError => e
      # Um usuário com problema não pode impedir a geração dos demais.
      Rails.error.report(e, handled: true, context: { user_id: user.id, job: self.class.name })
    end

    Rails.logger.info("[SyncRecurringEntriesJob] #{total} lançamento(s) gerado(s)")
    total
  end
end
