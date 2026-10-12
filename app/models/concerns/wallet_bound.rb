# Registro que pertence a um usuário E à carteira dele (lançamento ou template).
# Cada usuário tem uma única carteira, então ela nunca é escolhida pelo cliente:
# é atribuída ao criar e tem de ser a do próprio dono.
module WalletBound
  extend ActiveSupport::Concern

  included do
    belongs_to :user
    belongs_to :wallet

    before_validation :assign_user_wallet, on: :create
    validate :wallet_belongs_to_user
  end

  private

  def assign_user_wallet
    self.wallet ||= user&.wallet
  end

  # O banco só garante que o usuário e a carteira existem; sem isto, daria para
  # gravar um lançamento de A na carteira de B.
  def wallet_belongs_to_user
    return if wallet.nil? || user.nil? || wallet.user_id == user_id

    errors.add(:wallet, "não pertence ao usuário")
  end
end
