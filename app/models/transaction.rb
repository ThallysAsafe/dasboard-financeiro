# Um lançamento financeiro: receita ou despesa, conforme `kind`. O valor é sempre
# positivo; o sinal vem do tipo (receita soma, despesa subtrai).
class Transaction < ApplicationRecord
  KINDS = { income: 0, expense: 1 }.freeze

  belongs_to :user
  belongs_to :wallet, optional: true
  belongs_to :recurring_transaction, optional: true

  enum :kind, KINDS, validate: true

  validates :description, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
end
