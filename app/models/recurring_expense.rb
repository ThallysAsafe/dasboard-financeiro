class RecurringExpense < ApplicationRecord
  include RecurringSchedule

  has_many :expenses, dependent: :nullify

  def entries
    expenses
  end
end
