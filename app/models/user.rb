class User < ApplicationRecord
  has_secure_password

  has_many :wallets, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :recurring_transactions, dependent: :destroy

  # Normaliza na gravação e também nas buscas (find_by(email:)), então o login
  # não diferencia maiúsculas e a unicidade vale para Ana@x.com e ana@x.com.
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  # Só exige senha na criação ou quando ela está sendo trocada; senão não dá
  # para atualizar o e-mail sem reenviar a senha.
  MIN_PASSWORD_LENGTH = 10

  validates :password, presence: true, length: { minimum: MIN_PASSWORD_LENGTH },
                       if: -> { new_record? || !password.nil? }
  validate :password_differs_from_email, if: -> { password.present? }

  # Trocar a senha derruba as sessões abertas (tokens emitidos antes).
  before_update :bump_token_version, if: :will_save_change_to_password_digest?

  # Invalida todos os JWTs já emitidos para este usuário.
  def revoke_tokens!
    increment!(:token_version)
  end

  # Único caminho de login (REST e GraphQL). Devolve o usuário ou nil.
  # authenticate_by gasta o mesmo tempo de bcrypt mesmo quando o e-mail não
  # existe, então o tempo de resposta não revela quais e-mails estão cadastrados.
  def self.authenticate_with(email, password)
    return nil if email.blank? || password.blank?

    authenticate_by(email: email, password: password)
  end

  # Materializa os lançamentos devidos de todos os templates ativos.
  # Devolve quantos lançamentos foram criados no total.
  def sync_recurring_entries!(today: Date.current)
    recurring_transactions.active.sum { |template| template.generate_entries!(today: today) }
  end

  private

  def bump_token_version
    self.token_version += 1
  end

  def password_differs_from_email
    errors.add(:password, "não pode ser igual ao e-mail") if password.casecmp?(email.to_s)
  end
end
