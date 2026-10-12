# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    # Query: Perfil do usuário autenticado
    field :me, Types::UserType, null: true, description: "Retorna o perfil do usuário autenticado"
    def me
      context[:current_user]
    end

    # Query: Busca um usuário por ID. Só o próprio usuário pode ser consultado;
    # não existe listagem de usuários porque ela vazaria e-mails de terceiros.
    field :user, Types::UserType, null: true, description: "Busca o próprio usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def user(id:)
      require_user!
      raise GraphQL::ExecutionError, "Usuário não encontrado" unless id.to_s == context[:current_user].id.to_s

      context[:current_user]
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
      user = context[:current_user]
      # Somar Wallet#balance deixaria de fora os lançamentos sem carteira, que
      # ainda assim entram em totalIncome/totalExpense e fariam os três cards do
      # dashboard se contradizerem.
      user.wallets.sum(:initial_balance).to_f + user.incomes.sum(:amount).to_f - user.expenses.sum(:amount).to_f
    end

    # --- LANÇAMENTOS RECORRENTES ---
    field :recurring_incomes, [ Types::RecurringIncomeType ], null: false, description: "Lista as receitas recorrentes do usuário autenticado"
    def recurring_incomes
      require_user!
      context[:current_user].recurring_incomes.order(day_of_month: :asc)
    end

    field :recurring_income, Types::RecurringIncomeType, null: true, description: "Busca uma receita recorrente do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def recurring_income(id:)
      require_user!
      context[:current_user].recurring_incomes.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Receita recorrente não encontrada"
    end

    field :recurring_expenses, [ Types::RecurringExpenseType ], null: false, description: "Lista as despesas recorrentes do usuário autenticado"
    def recurring_expenses
      require_user!
      context[:current_user].recurring_expenses.order(day_of_month: :asc)
    end

    field :recurring_expense, Types::RecurringExpenseType, null: true, description: "Busca uma despesa recorrente do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def recurring_expense(id:)
      require_user!
      context[:current_user].recurring_expenses.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Despesa recorrente não encontrada"
    end

    private

    def require_user!
      raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
    end
  end
end
