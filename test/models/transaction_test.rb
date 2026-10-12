require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  def build(attrs = {})
    users(:one).transactions.build({ kind: :income, description: "Salário", amount: 100,
                                     date: Date.new(2026, 8, 1) }.merge(attrs))
  end

  test "é válida com tipo, descrição, valor positivo e data" do
    assert build.valid?
    assert build(kind: :expense).valid?
  end

  test "exige descrição, valor e data" do
    assert_not build(description: "").valid?
    assert_not build(amount: nil).valid?
    assert_not build(date: nil).valid?
  end

  test "o valor tem de ser positivo; o sinal vem do tipo" do
    assert_not build(amount: 0).valid?
    assert_not build(amount: -5).valid?
  end

  test "kind é obrigatório e restrito a receita ou despesa" do
    assert_not build(kind: nil).valid?
    assert_not build(kind: :transferencia).valid? # validate: true no enum, sem ArgumentError
  end

  test "scopes e predicados por tipo" do
    income = users(:one).transactions.income
    expense = users(:one).transactions.expense

    assert income.all?(&:income?)
    assert expense.all?(&:expense?)
    assert_equal users(:one).transactions.count, income.count + expense.count
  end

  test "carteira e recorrência são opcionais" do
    assert build(wallet: nil, recurring_transaction: nil).valid?
  end

  test "o banco rejeita lançamento sem tipo, valor ou data" do
    t = build(kind: nil)
    assert_raises(ActiveRecord::NotNullViolation) { t.save!(validate: false) }
  end

  test "a mesma data não se repete dentro de uma recorrência (índice único)" do
    template = users(:one).recurring_transactions.create!(
      kind: :income, description: "Salário", amount: 100, day_of_month: 5, start_date: Date.new(2026, 8, 5)
    )
    template.transactions.create!(kind: :income, user: users(:one), description: "S", amount: 100, date: Date.new(2026, 8, 5))
    duplicate = template.transactions.build(kind: :income, user: users(:one), description: "S", amount: 100, date: Date.new(2026, 8, 5))

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
