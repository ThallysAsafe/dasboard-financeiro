class User < ApplicationRecord
  has_secure_password

  # A carteira vai primeiro: apagá-la leva os lançamentos e templates junto.
  has_one :wallet, dependent: :destroy
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
  DEFAULT_WALLET_NAME = "Carteira".freeze

  validates :password, presence: true, length: { minimum: MIN_PASSWORD_LENGTH },
                       if: -> { new_record? || !password.nil? }
  validate :password_differs_from_email, if: -> { password.present? }

  after_create :create_default_wallet

  # Tokens assinados (sem coluna no banco). O bloco entra na assinatura: quando o valor
  # muda, o token antigo deixa de valer.
  # - redefinição de senha: vale 30 min e UMA vez só, porque embute um pedaço do hash da
  #   senha, que muda assim que a senha é trocada
  # - confirmação de e-mail: vale 3 dias e invalida se o e-mail mudar
  generates_token_for :password_reset, expires_in: 30.minutes do
    password_salt&.last(10)
  end
  generates_token_for :email_confirmation, expires_in: 3.days do
    email
  end

  # Trocar o e-mail zera a confirmação e pede outra; criar a conta também envia uma.
  before_update :unconfirm_email, if: :will_save_change_to_email?
  # Um único callback: after_create_commit e after_update_commit com o MESMO método se
  # anulam (só o último vale). Na criação o e-mail também "muda" (de vazio para um valor).
  after_commit :send_email_confirmation, on: %i[create update], if: :saved_change_to_email?

  # Trocar a senha derruba as sessões abertas (tokens emitidos antes).
  before_update :bump_token_version, if: :will_save_change_to_password_digest?

  def email_confirmed?
    email_confirmed_at.present?
  end

  def confirm_email!
    update!(email_confirmed_at: Time.current) unless email_confirmed?
  end

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

  def unconfirm_email
    self.email_confirmed_at = nil
  end

  def send_email_confirmation
    UserMailer.email_confirmation(self).deliver_later
  end

  def create_default_wallet
    create_wallet!(name: DEFAULT_WALLET_NAME, initial_balance: 0)
  end

  def bump_token_version
    self.token_version += 1
  end

  def password_differs_from_email
    errors.add(:password, "não pode ser igual ao e-mail") if password.casecmp?(email.to_s)
  end
end
