class Wallet < ApplicationRecord
  belongs_to :user
  has_many :incomes, dependent: :destroy
  has_many :expenses, dependent: :destroy

  # Nullify para que apagar a carteira não bloqueie por FK nem leve junto os
  # templates: eles seguem valendo, passando a gerar lançamentos sem carteira.
  has_many :recurring_incomes, dependent: :nullify
  has_many :recurring_expenses, dependent: :nullify

  validates :name, presence: true
  validates :initial_balance, presence: true, numericality: true

  def total_income
    incomes.sum(:amount).to_f
  end

  def total_expense
    expenses.sum(:amount).to_f
  end

  def balance
    (initial_balance || 0).to_f + total_income - total_expense
  end
end
