require "test_helper"

# O agendamento é configuração (config/application.rb); estes testes garantem que
# ela aponta para o job certo, no horário certo e no modo que dispensa worker.
class SchedulerConfigTest < ActiveJob::TestCase
  def entry
    Rails.application.config.good_job.cron.fetch(:sync_recurring_entries)
  end

  test "o cron diário aponta para o job de recorrência" do
    assert_equal SyncRecurringEntriesJob, entry[:class].constantize
    assert entry[:description].present?
  end

  test "a expressão é válida e roda todo dia às 00:05 no horário de Brasília" do
    cron = Fugit.parse_cron(entry[:cron])
    assert cron, "expressão cron inválida: #{entry[:cron]}"

    # 12:00 UTC de 12/10 = 09:00 em Brasília -> a próxima é a meia-noite seguinte
    proximo = cron.next_time(Time.utc(2026, 10, 12, 12)).to_t.in_time_zone("America/Sao_Paulo")
    assert_equal [ 13, 0, 5 ], [ proximo.day, proximo.hour, proximo.min ]

    seguinte = cron.next_time(proximo.utc).to_t.in_time_zone("America/Sao_Paulo")
    assert_equal [ 14, 0, 5 ], [ seguinte.day, seguinte.hour, seguinte.min ]
  end

  test "roda dentro do processo web (async), sem exigir um worker separado" do
    assert_equal :async, Rails.application.config.good_job.execution_mode
  end

  test "nos testes o cron fica desligado e os jobs não rodam sozinhos" do
    assert_not Rails.application.config.good_job.enable_cron
    assert_instance_of ActiveJob::QueueAdapters::TestAdapter, ActiveJob::Base.queue_adapter
  end

  test "o job pode ser enfileirado pelo scheduler" do
    assert_enqueued_with(job: SyncRecurringEntriesJob) { SyncRecurringEntriesJob.perform_later }
  end
end
