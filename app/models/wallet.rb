class Wallet < ApplicationRecord
  belongs_to :user
  has_many :incomes, dependent: :destroy
  has_many :expenses, dependent: :destroy

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
