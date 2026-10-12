class RecurringIncome < ApplicationRecord
  include RecurringSchedule

  # Nullify e não destroy: os lançamentos já gerados aconteceram de verdade e
  # continuam valendo para o saldo histórico mesmo sem o template.
  has_many :incomes, dependent: :nullify

  def entries
    incomes
  end
end
