# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :user_login, mutation: Mutations::User::UserLogin
    field :user_create, mutation: Mutations::User::UserCreate
    field :user_update, mutation: Mutations::User::UserUpdate
    field :user_delete, mutation: Mutations::User::UserDelete

    # Mutations de Receita (Income)
    field :income_create, mutation: Mutations::Income::IncomeCreate
    field :income_update, mutation: Mutations::Income::IncomeUpdate
    field :income_delete, mutation: Mutations::Income::IncomeDelete

    # Mutations de Despesa (Expense)
    field :expense_create, mutation: Mutations::Expense::ExpenseCreate
    field :expense_update, mutation: Mutations::Expense::ExpenseUpdate
    field :expense_delete, mutation: Mutations::Expense::ExpenseDelete
  end
end
