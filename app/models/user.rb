class User < ApplicationRecord
  has_secure_password

  has_many :wallets, dependent: :destroy
  has_many :incomes, dependent: :destroy
  has_many :expenses, dependent: :destroy
  has_many :recurring_incomes, dependent: :destroy
  has_many :recurring_expenses, dependent: :destroy

  # Normaliza na gravação e também nas buscas (find_by(email:)), então o login
  # não diferencia maiúsculas e a unicidade vale para Ana@x.com e ana@x.com.
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  # Só exige senha na criação ou quando ela está sendo trocada; senão não dá
  # para atualizar o e-mail sem reenviar a senha.
  validates :password, presence: true, length: { minimum: 6 }, if: -> { new_record? || !password.nil? }

  # Materializa os lançamentos devidos de todos os templates ativos.
  # Devolve quantos lançamentos foram criados no total.
  def sync_recurring_entries!(today: Date.current)
    recurring_incomes.active.sum { |template| template.generate_entries!(today: today) } +
      recurring_expenses.active.sum { |template| template.generate_entries!(today: today) }
  end
end
