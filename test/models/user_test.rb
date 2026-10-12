require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "sync_recurring_entries! soma receitas e despesas e é idempotente" do
    user = users(:one)
    user.recurring_incomes.create!(
      description: "Salário", amount: 5000, day_of_month: 5, start_date: Date.new(2026, 1, 5)
    )
    user.recurring_expenses.create!(
      description: "Aluguel", amount: 1500, day_of_month: 10, start_date: Date.new(2026, 2, 10)
    )

    # 3 receitas (jan, fev, mar) + 2 despesas (fev, mar)
    assert_equal 5, User.find(user.id).sync_recurring_entries!(today: Date.new(2026, 3, 31))
    assert_equal 0, User.find(user.id).sync_recurring_entries!(today: Date.new(2026, 3, 31))
  end

  test "sync_recurring_entries! ignora templates pausados" do
    user = users(:two)
    user.recurring_incomes.create!(
      description: "Freela", amount: 800, day_of_month: 1,
      start_date: Date.new(2026, 1, 1), active: false
    )

    assert_equal 0, User.find(user.id).sync_recurring_entries!(today: Date.new(2026, 6, 1))
  end

  test "o banco rejeita e-mail duplicado mesmo sem passar pela validação" do
    duplicate = User.new(email: users(:one).email, password: "123456")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "atualizar o e-mail não exige reenviar a senha, mas trocá-la valida o tamanho" do
    user = User.find(users(:one).id)

    assert user.update(email: "novo@exemplo.com")
    assert_not user.update(password: "123")
  end
end
