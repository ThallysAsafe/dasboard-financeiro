require "test_helper"

# Smoke test: a lógica de agendamento é a mesma de RecurringIncome (concern
# RecurringSchedule) e está coberta lá. Aqui só se confere que o outro lado do
# espelho gera Expense e solta os lançamentos ao ser apagado.
class RecurringExpenseTest < ActiveSupport::TestCase
  test "gera despesas e as preserva ao apagar o template" do
    user = users(:one)
    t = user.recurring_expenses.create!(
      description: "Aluguel", amount: 1500, day_of_month: 10,
      start_date: Date.new(2026, 1, 10), wallet: wallets(:one)
    )

    assert_equal 3, t.generate_entries!(today: Date.new(2026, 3, 10))
    assert_equal 0, t.generate_entries!(today: Date.new(2026, 3, 10))

    ids = t.expenses.pluck(:id)
    t.destroy

    assert_equal ids.count, Expense.where(id: ids).count
    assert_equal [ nil ], Expense.where(id: ids).pluck(:recurring_expense_id).uniq
  end
end
