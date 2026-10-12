# A carteira do usuário: guarda o saldo inicial, e o saldo atual é esse valor
# mais as receitas e menos as despesas. Cada usuário tem exatamente uma (índice
# único em user_id), criada junto com ele; ela só deixa de existir com o usuário.
class Wallet < ApplicationRecord
  belongs_to :user

  has_many :transactions, dependent: :destroy
  has_many :recurring_transactions, dependent: :destroy

  validates :name, presence: true
  validates :initial_balance, presence: true, numericality: true
  validates :user_id, uniqueness: true

  def total_income
    transactions.income.sum(:amount).to_f
  end

  def total_expense
    transactions.expense.sum(:amount).to_f
  end

  def balance
    (initial_balance || 0).to_f + total_income - total_expense
  end
end
