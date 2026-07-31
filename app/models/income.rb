class Income < ApplicationRecord
  belongs_to :user
  belongs_to :wallet, optional: true

  validates :description, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
end
