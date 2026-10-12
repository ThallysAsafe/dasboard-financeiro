class Wallet < ApplicationRecord
  belongs_to :user
  has_many :transactions, dependent: :destroy

  # Nullify para que apagar a carteira não bloqueie por FK nem leve junto os
  # templates: eles seguem valendo, passando a gerar lançamentos sem carteira.
  has_many :recurring_transactions, dependent: :nullify

  validates :name, presence: true
  validates :initial_balance, presence: true, numericality: true

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
