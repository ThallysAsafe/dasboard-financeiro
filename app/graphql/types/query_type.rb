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

    # --- RESUMO FINANCEIRO ---
    field :total_income, Float, null: false, description: "Soma total das receitas do usuário"
    def total_income
      require_user!
      context[:current_user].incomes.sum(:amount).to_f
    end

    field :total_expense, Float, null: false, description: "Soma total das despesas do usuário"
    def total_expense
      require_user!
      context[:current_user].expenses.sum(:amount).to_f
    end

    field :balance, Float, null: false, description: "Saldo total (Receitas - Despesas) do usuário"
    def balance
      total_income - total_expense
    end

    private

    def require_user!
      raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
    end
  end
end
