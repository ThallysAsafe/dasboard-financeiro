namespace :recurring do
  desc "Gera os lançamentos recorrentes devidos de todos os usuários (rodar 1x ao dia)"
  task sync: :environment do
    puts "#{SyncRecurringEntriesJob.perform_now} lançamento(s) gerado(s)"
  end
end
