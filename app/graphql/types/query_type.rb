# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    # Query: Perfil do usuário autenticado
    field :me, Types::UserType, null: true, description: "Retorna o perfil do usuário autenticado"
    def me
      context[:current_user]
    end

    # Query: Listar usuários
    field :users, [Types::UserType], null: false, description: "Lista todos os usuários"
    def users
      require_user!
      User.all
    end

    field :user, Types::UserType, null: true, description: "Busca um usuário por ID" do
      argument :id, ID, required: true
    end
    def user(id:)
      require_user!
      User.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Usuário não encontrado"
    end

    # --- QUERIES DE CARTEIRAS (WALLETS) ---
    field :wallets, [Types::WalletType], null: false, description: "Lista todas as carteiras do usuário autenticado"
    def wallets
      require_user!
      context[:current_user].wallets.order(created_at: :asc)
    end

    field :wallet, Types::WalletType, null: true, description: "Busca uma carteira do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def wallet(id:)
      require_user!
      context[:current_user].wallets.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Carteira não encontrada"
    end

    # --- QUERIES DE RECEITAS (INCOMES) ---
    field :incomes, [Types::IncomeType], null: false, description: "Lista todas as receitas do usuário autenticado"
    def incomes
      require_user!
      context[:current_user].incomes.order(date: :desc)
    end

    field :income, Types::IncomeType, null: true, description: "Busca uma receita do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def income(id:)
      require_user!
      context[:current_user].incomes.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Receita não encontrada"
    end

    # --- QUERIES DE DESPESAS (EXPENSES) ---
    field :expenses, [Types::ExpenseType], null: false, description: "Lista todas as despesas do usuário autenticado"
    def expenses
      require_user!
      context[:current_user].expenses.order(date: :desc)
    end

    field :expense, Types::ExpenseType, null: true, description: "Busca uma despesa do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def expense(id:)
      require_user!
      context[:current_user].expenses.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Despesa não encontrada"
    end

    # --- RESUMO FINANCEIRO GERAL ---
    field :total_income, Float, null: false, description: "Soma total de todas as receitas do usuário"
    def total_income
      require_user!
      context[:current_user].incomes.sum(:amount).to_f
    end

    field :total_expense, Float, null: false, description: "Soma total de todas as despesas do usuário"
    def total_expense
      require_user!
      context[:current_user].expenses.sum(:amount).to_f
    end

    field :balance, Float, null: false, description: "Saldo total geral (Saldo das carteiras + Receitas - Despesas)"
    def balance
      require_user!
      context[:current_user].wallets.sum(&:balance)
    end

    private

    def require_user!
      raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
    end
  end
end
