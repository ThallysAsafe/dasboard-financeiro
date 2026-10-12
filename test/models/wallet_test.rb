require "test_helper"

class WalletTest < ActiveSupport::TestCase
  test "criar um usuário cria a carteira dele" do
    user = User.create!(email: "novo@exemplo.com", password: "senhaforte123")

    assert_equal 1, Wallet.where(user_id: user.id).count
    assert_equal User::DEFAULT_WALLET_NAME, user.wallet.name
    assert_equal 0, user.wallet.initial_balance
  end

  test "cada usuário tem uma só carteira: a validação recusa a segunda" do
    second = Wallet.new(user: users(:one), name: "Outra", initial_balance: 0)

    assert_not second.valid?
    assert second.errors.of_kind?(:user_id, :taken)
  end

  test "o banco também recusa a segunda carteira (índice único)" do
    second = Wallet.new(user: users(:one), name: "Outra", initial_balance: 0)

    assert_raises(ActiveRecord::RecordNotUnique) { second.save!(validate: false) }
  end

  test "o saldo é o saldo inicial mais receitas menos despesas" do
    wallet = users(:one).wallet
    wallet.update!(initial_balance: 100)
    wallet.transactions.delete_all
    users(:one).transactions.create!(kind: :income, description: "R", amount: 50, date: Date.new(2026, 8, 1))
    users(:one).transactions.create!(kind: :expense, description: "D", amount: 30, date: Date.new(2026, 8, 2))

    assert_equal 50.0, wallet.total_income
    assert_equal 30.0, wallet.total_expense
    assert_equal 120.0, wallet.balance
  end

  test "o saldo ignora os lançamentos de outro usuário" do
    wallet = users(:one).wallet
    before = wallet.balance
    users(:two).transactions.create!(kind: :income, description: "Alheio", amount: 999, date: Date.new(2026, 8, 1))

    assert_equal before, wallet.reload.balance
  end

  test "apagar o usuário leva a carteira, os lançamentos e as recorrências" do
    user = users(:one)
    user.recurring_transactions.create!(kind: :income, description: "S", amount: 1, day_of_month: 1, start_date: Date.new(2026, 8, 1))

    assert_difference [ "Wallet.count", "RecurringTransaction.count" ], -1 do
      assert_difference "Transaction.count", -user.transactions.count do
        user.destroy
      end
    end
  end

  test "nome e saldo inicial são obrigatórios" do
    wallet = users(:one).wallet

    wallet.name = ""
    assert_not wallet.valid?
    wallet.name = "Ok"
    wallet.initial_balance = nil
    assert_not wallet.valid?
  end
end
