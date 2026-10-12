require "test_helper"

# A lógica real vive em RecurringSchedule, compartilhada com RecurringExpense.
# É aqui que ela é exercitada por inteiro; recurring_expense_test.rb só confere
# que a concern está ligada do outro lado.
class RecurringIncomeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @wallet = wallets(:one)
  end

  def template(attrs = {})
    @user.recurring_incomes.create!({
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
    assert_equal 3, t.incomes.count
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
    assert_equal 0, t.incomes.count
  end

  test "limita a retroação de um template muito antigo" do
    hoje = Date.new(2026, 8, 9)
    t = template(start_date: hoje - 30.years)

    criados = t.generate_entries!(today: hoje)

    assert_operator criados, :<=, RecurringSchedule::MAX_BACKFILL_MONTHS
    assert_operator t.incomes.minimum(:date), :>=, hoje - RecurringSchedule::MAX_BACKFILL_MONTHS.months
  end

  test "lançamento apagado pelo usuário não é recriado" do
    t = template(day_of_month: 31, start_date: Date.new(2026, 1, 31))
    t.generate_entries!(today: Date.new(2026, 3, 31))
    t.incomes.order(:date).first.destroy

    assert_equal 0, t.generate_entries!(today: Date.new(2026, 3, 31))
    assert_equal 2, t.incomes.count
  end

  test "apagar o template preserva os lançamentos já gerados" do
    t = template(start_date: Date.new(2026, 1, 5))
    t.generate_entries!(today: Date.new(2026, 3, 5))
    ids = t.incomes.pluck(:id)

    t.destroy

    assert_equal ids.count, Income.where(id: ids).count
    assert_equal [ nil ], Income.where(id: ids).pluck(:recurring_income_id).uniq
  end

  test "copia os atributos do template para o lançamento gerado" do
    t = template(start_date: Date.new(2026, 1, 5), category: "Trabalho")
    t.generate_entries!(today: Date.new(2026, 1, 5))
    income = t.incomes.first

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
    invalido = @user.recurring_incomes.build(
      description: "X", amount: 10, day_of_month: 5,
      start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 4, 1)
    )

    assert_not invalido.valid?
    assert_includes invalido.errors[:end_date], "deve ser igual ou posterior à data de início"
  end

  test "valida dia do mês entre 1 e 31" do
    assert_not @user.recurring_incomes.build(
      description: "X", amount: 10, day_of_month: 32, start_date: Date.current
    ).valid?
  end
end
