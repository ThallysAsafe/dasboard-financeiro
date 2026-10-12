# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    # Mutations de Autenticação / Usuário
    field :user_login, mutation: Mutations::User::UserLogin
    field :user_create, mutation: Mutations::User::UserCreate
    field :user_update, mutation: Mutations::User::UserUpdate
    field :user_delete, mutation: Mutations::User::UserDelete

    # Mutations de Carteira (Wallet)
    field :wallet_create, mutation: Mutations::Wallet::WalletCreate
    field :wallet_update, mutation: Mutations::Wallet::WalletUpdate
    field :wallet_delete, mutation: Mutations::Wallet::WalletDelete

    # Mutations de Lançamento (receita ou despesa, conforme `kind`)
    field :transaction_create, mutation: Mutations::Transaction::TransactionCreate
    field :transaction_update, mutation: Mutations::Transaction::TransactionUpdate
    field :transaction_delete, mutation: Mutations::Transaction::TransactionDelete

    # Mutations de Lançamento Recorrente
    field :recurring_transaction_create, mutation: Mutations::RecurringTransaction::RecurringTransactionCreate
    field :recurring_transaction_update, mutation: Mutations::RecurringTransaction::RecurringTransactionUpdate
    field :recurring_transaction_delete, mutation: Mutations::RecurringTransaction::RecurringTransactionDelete

    # Geração automática dos lançamentos recorrentes devidos
    field :sync_recurring_entries, mutation: Mutations::Recurring::SyncRecurringEntries
  end
end
