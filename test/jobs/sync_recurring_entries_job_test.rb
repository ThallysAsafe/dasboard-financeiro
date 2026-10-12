require "test_helper"
require "rake"

class SyncRecurringEntriesJobTest < ActiveJob::TestCase
  def template(user, **attrs)
    user.recurring_transactions.create!({ kind: :income, description: "Salário", amount: 5000, day_of_month: 5,
                                     start_date: Date.new(2026, 6, 5) }.merge(attrs))
  end

  test "gera os lançamentos devidos de todos os usuários" do
    template(users(:one))
    template(users(:two), description: "Freela")

    travel_to Time.zone.local(2026, 8, 9, 12) do
      # junho, julho e agosto para cada um
      assert_equal 6, SyncRecurringEntriesJob.perform_now
    end

    assert_equal 3, users(:one).transactions.where.not(recurring_transaction_id: nil).count
    assert_equal 3, users(:two).transactions.where.not(recurring_transaction_id: nil).count
  end

  test "rodar de novo não duplica" do
    template(users(:one))

    travel_to Time.zone.local(2026, 8, 9, 12) do
      SyncRecurringEntriesJob.perform_now
      assert_no_difference "Transaction.count" do
        assert_equal 0, SyncRecurringEntriesJob.perform_now
      end
    end
  end

  test "um usuário com erro não impede os demais" do
    template(users(:one))
    template(users(:two))
    quebrado = users(:one)
    original = User.instance_method(:sync_recurring_entries!)

    User.class_eval do
      define_method(:sync_recurring_entries!) do |**args|
        raise "falha simulada" if id == quebrado.id

        original.bind(self).call(**args)
      end
    end

    begin
      travel_to Time.zone.local(2026, 8, 9, 12) do
        assert_equal 3, SyncRecurringEntriesJob.perform_now
      end
    ensure
      User.send(:define_method, :sync_recurring_entries!, original)
    end

    assert_equal 0, users(:one).transactions.where.not(recurring_transaction_id: nil).count
    assert_equal 3, users(:two).transactions.where.not(recurring_transaction_id: nil).count
  end

  test "à noite em Brasília ainda é o dia local: não gera a ocorrência do dia seguinte" do
    template(users(:one), day_of_month: 10, start_date: Date.new(2026, 8, 10))

    # 01:00 UTC de 10/08 = 22:00 de 09/08 em Brasília
    travel_to Time.utc(2026, 8, 10, 1) do
      assert_equal Date.new(2026, 8, 9), Date.current
      assert_equal 0, SyncRecurringEntriesJob.perform_now
    end

    travel_to Time.utc(2026, 8, 10, 12) do
      assert_equal 1, SyncRecurringEntriesJob.perform_now
    end
  end

  test "a rake task executa o job" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("recurring:sync")
    template(users(:one))

    travel_to Time.zone.local(2026, 8, 9, 12) do
      assert_output(/3 lançamento\(s\) gerado\(s\)/) { Rake::Task["recurring:sync"].execute }
    end
  end
end
