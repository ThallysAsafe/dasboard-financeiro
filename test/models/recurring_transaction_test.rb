require "test_helper"

# Regras de agendamento da recorrência (clamp de dia, backfill, idempotência…).
# Os cenários usam receitas; o kind só importa no teste de despesa no final.
class RecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @wallet = wallets(:one)
  end

  def template(attrs = {})
    @user.recurring_transactions.create!({
      kind: :income,
      description: "Salário",
      amount: 5000,
      day_of_month: 5,
      start_date: Date.new(2026, 1, 5),
      wallet: @wallet
    }.merge(attrs))
  end

  test "trava o dia no último dia válido de meses curtos" do
    t = template(day_of_month: 31, start_date: Date.new(2026, 1, 31))

    assert_equal [ Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31) ],
                 t.occurrence_dates(today: Date.new(2026, 3, 31))
  end

  test "usa 29 de fevereiro em ano bissexto" do
    t = template(day_of_month: 31, start_date: Date.new(2028, 2, 1))

    assert_equal [ Date.new(2028, 2, 29) ], t.occurrence_dates(today: Date.new(2028, 2, 29))
  end

  test "gerar duas vezes não duplica lançamentos" do
    t = template(day_of_month: 31, start_date: Date.new(2026, 1, 31))

    assert_equal 3, t.generate_entries!(today: Date.new(2026, 3, 31))
    assert_equal 0, t.generate_entries!(today: Date.new(2026, 3, 31))
    assert_equal 3, t.transactions.count
  end

  test "ignora ocorrências anteriores à data de início" do
    t = template(day_of_month: 5, start_date: Date.new(2026, 1, 20))

    assert_equal Date.new(2026, 2, 5), t.occurrence_dates(today: Date.new(2026, 3, 1)).first
  end

  test "trata end_date como limite inclusivo" do
    dentro = template(day_of_month: 10, end_date: Date.new(2026, 2, 15))
    assert_equal Date.new(2026, 2, 10), dentro.occurrence_dates(today: Date.new(2026, 6, 1)).last

    fora = template(day_of_month: 10, end_date: Date.new(2026, 2, 5))
    assert_not_includes fora.occurrence_dates(today: Date.new(2026, 6, 1)), Date.new(2026, 2, 10)
  end

  test "nunca cria lançamento com data futura" do
    t = template(day_of_month: 10, start_date: Date.new(2026, 8, 1))

    assert_empty t.occurrence_dates(today: Date.new(2026, 8, 3))
    assert_equal 0, t.generate_entries!(today: Date.new(2026, 8, 3))
    assert_equal [ Date.new(2026, 8, 10) ], t.occurrence_dates(today: Date.new(2026, 8, 10))
  end

  test "template pausado não gera nada" do
    t = template(active: false, start_date: Date.new(2026, 1, 5))

    assert_equal 0, t.generate_entries!(today: Date.new(2026, 6, 5))
    assert_equal 0, t.transactions.count
  end

  test "limita a retroação a exatamente 120 meses, mantendo os mais recentes" do
    hoje = Date.new(2026, 8, 9)
    t = template(day_of_month: 5)
    # A validação já recusa início tão antigo; aqui interessa o corte do backfill em
    # si, então força a data por fora (como num template criado antes do limite).
    t.update_columns(start_date: hoje - 30.years)

    criados = t.generate_entries!(today: hoje)

    assert_equal RecurringTransaction::MAX_BACKFILL_MONTHS, criados
    # Janela fechada de 120 meses: de set/2016 a ago/2026. O corte descarta os
    # meses antigos, nunca os recentes.
    assert_equal Date.new(2016, 9, 5), t.transactions.minimum(:date)
    assert_equal Date.new(2026, 8, 5), t.transactions.maximum(:date)
  end

  test "lançamento apagado pelo usuário não é recriado" do
    t = template(day_of_month: 31, start_date: Date.new(2026, 1, 31))
    t.generate_entries!(today: Date.new(2026, 3, 31))
    t.transactions.order(:date).first.destroy

    assert_equal 0, t.generate_entries!(today: Date.new(2026, 3, 31))
    assert_equal 2, t.transactions.count
  end

  test "apagar o template preserva os lançamentos já gerados" do
    t = template(start_date: Date.new(2026, 1, 5))
    t.generate_entries!(today: Date.new(2026, 3, 5))
    ids = t.transactions.pluck(:id)

    t.destroy

    assert_equal ids.count, Transaction.where(id: ids).count
    assert_equal [ nil ], Transaction.where(id: ids).pluck(:recurring_transaction_id).uniq
  end

  test "copia os atributos do template para o lançamento gerado" do
    t = template(start_date: Date.new(2026, 1, 5), category: "Trabalho")
    t.generate_entries!(today: Date.new(2026, 1, 5))
    income = t.transactions.first
    assert income.income?

    assert_equal "Salário", income.description
    assert_equal 5000, income.amount
    assert_equal "Trabalho", income.category
    assert_equal @wallet.id, income.wallet_id
    assert_equal @user.id, income.user_id
  end

  test "next_occurrence devolve a próxima data travada no mês" do
    t = template(day_of_month: 31, start_date: Date.new(2026, 1, 31))

    assert_equal Date.new(2026, 4, 30), t.next_occurrence(today: Date.new(2026, 3, 31))
  end

  test "next_occurrence devolve nil quando a recorrência acabou ou está pausada" do
    encerrada = template(day_of_month: 5, end_date: Date.new(2026, 3, 5))
    assert_nil encerrada.next_occurrence(today: Date.new(2026, 6, 1))

    assert_nil template(active: false).next_occurrence(today: Date.new(2026, 1, 1))
  end

  test "exige end_date igual ou posterior ao início" do
    invalido = @user.recurring_transactions.build(
      description: "X", amount: 10, day_of_month: 5,
      start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 4, 1)
    )

    assert_not invalido.valid?
    assert_includes invalido.errors[:end_date], "deve ser igual ou posterior à data de início"
  end

  test "valida dia do mês entre 1 e 31" do
    assert_not @user.recurring_transactions.build(
      description: "X", amount: 10, day_of_month: 32, start_date: Date.current
    ).valid?
  end

  test "template de despesa gera despesas e as preserva ao ser apagado" do
    t = template(kind: :expense, description: "Aluguel", amount: 1500, day_of_month: 10,
                 start_date: Date.new(2026, 1, 10))

    assert_equal 3, t.generate_entries!(today: Date.new(2026, 3, 31))
    assert t.transactions.all?(&:expense?)

    assert_no_difference "Transaction.count" do
      t.destroy
    end
    assert_equal 3, @user.transactions.expense.where(description: "Aluguel").count
    assert_nil @user.transactions.expense.find_by(description: "Aluguel").recurring_transaction_id
  end

  test "exige um kind válido" do
    t = @user.recurring_transactions.build(description: "X", amount: 1, day_of_month: 1,
                                           start_date: Date.new(2026, 1, 1))

    assert_not t.valid?
    assert t.errors.of_kind?(:kind, :inclusion)
  end

  # --- janela de retroação

  test "recusa data de início anterior à janela de 120 meses, em vez de cortar em silêncio" do
    hoje = Date.current
    antigo = @user.recurring_transactions.build(kind: :income, description: "Velho", amount: 1, day_of_month: 5,
                                                start_date: RecurringTransaction.earliest_start_date(today: hoje) - 1.day)

    assert_not antigo.valid?
    assert antigo.errors[:start_date].first.include?("limite de retroação é de 120 meses")
    assert antigo.errors[:start_date].first.match?(%r{\d{2}/\d{2}/\d{4}}), "mostra a data limite em pt-BR"
  end

  test "aceita exatamente o primeiro mês da janela" do
    limite = RecurringTransaction.earliest_start_date
    t = @user.recurring_transactions.build(kind: :income, description: "No limite", amount: 1, day_of_month: 5, start_date: limite)

    assert t.valid?, t.errors.full_messages.inspect
    datas = t.occurrence_dates
    # A ocorrência deste mês pode ainda não ter chegado (dia 5 e hoje é dia 2), então
    # são 120 ou 119; o que importa é começar no primeiro mês da janela.
    assert_equal limite.beginning_of_month, datas.first.beginning_of_month
    assert_operator datas.size, :>=, RecurringTransaction::MAX_BACKFILL_MONTHS - 1
  end

  test "o limite acompanha a data de hoje" do
    assert_equal Date.new(2016, 9, 1), RecurringTransaction.earliest_start_date(today: Date.new(2026, 8, 9))
    assert_equal Date.new(2017, 2, 1), RecurringTransaction.earliest_start_date(today: Date.new(2027, 1, 31))
  end

  test "mudar a data de início para antes da janela também é recusado" do
    t = template(start_date: Date.current.beginning_of_month)
    t.start_date = RecurringTransaction.earliest_start_date - 1.month

    assert_not t.valid?
    assert t.errors.key?(:start_date)
  end

  test "um template antigo continua podendo ser pausado e editado" do
    t = template(day_of_month: 5)
    t.update_columns(start_date: Date.current - 15.years, last_generated_on: Date.current) # já gerou tudo

    assert t.update(active: false)
    assert t.update(description: "Novo nome")
    assert t.reload.valid?, "não valida de novo a data de início se ela não mudou"
  end

  test "recusa valor acima do máximo da coluna" do
    t = @user.recurring_transactions.build(kind: :income, description: "X", amount: 10**12, day_of_month: 5,
                                           start_date: Date.current.beginning_of_month)

    assert_not t.valid?
    assert t.errors.key?(:amount)
  end
end
