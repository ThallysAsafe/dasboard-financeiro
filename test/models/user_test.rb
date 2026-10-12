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

  test "e-mail é normalizado (minúsculas, sem espaços) ao salvar" do
    user = User.create!(email: "  Ana@Exemplo.COM ", password: "123456")

    assert_equal "ana@exemplo.com", user.email
  end

  test "e-mail não pode repetir mudando só a caixa" do
    duplicate = User.new(email: users(:one).email.upcase, password: "123456")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:email, :taken)
  end

  test "busca por e-mail ignora a caixa" do
    assert_equal users(:one), User.find_by(email: users(:one).email.upcase)
  end

  test "e-mail com formato inválido é rejeitado" do
    %w[sem-arroba @x.com a@].each do |invalid|
      assert_not User.new(email: invalid, password: "123456").valid?, "#{invalid} deveria ser inválido"
    end
  end

  test "find_by com espaços e outra caixa encontra o usuário (base do login)" do
    assert_equal users(:one), User.find_by(email: " UM@exemplo.com ")&.authenticate("123456")
  end
end
