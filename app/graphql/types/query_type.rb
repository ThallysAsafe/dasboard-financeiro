# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    include Types::Pagination

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
    field :wallets, [ Types::WalletType ], null: false, description: "Lista todas as carteiras do usuário autenticado"
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

    # --- LANÇAMENTOS (RECEITAS E DESPESAS) ---
    field :transactions, [ Types::TransactionType ], null: false,
          description: "Lista os lançamentos do usuário autenticado, do mais recente ao mais antigo (paginado)" do
      argument :kind, Types::TransactionKindEnum, required: false, description: "Só receitas ou só despesas"
      argument :limit, Integer, required: false, default_value: Types::Pagination::DEFAULT_PAGE_SIZE,
               description: "Máximo de #{Types::Pagination::MAX_PAGE_SIZE}"
      argument :offset, Integer, required: false, default_value: 0
    end
    def transactions(limit:, offset:, kind: nil)
      require_user!
      scope = context[:current_user].transactions.includes(:wallet)
      scope = scope.where(kind: kind) if kind
      paginate(scope.order(date: :desc, id: :desc), limit, offset)
    end

    field :transaction, Types::TransactionType, null: true, description: "Busca um lançamento do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def transaction(id:)
      require_user!
      context[:current_user].transactions.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Lançamento não encontrado"
    end

    # --- RESUMO FINANCEIRO GERAL ---
    field :total_income, Float, null: false, description: "Soma total de todas as receitas do usuário"
    def total_income
      require_user!
      context[:current_user].transactions.income.sum(:amount).to_f
    end

    field :total_expense, Float, null: false, description: "Soma total de todas as despesas do usuário"
    def total_expense
      require_user!
      context[:current_user].transactions.expense.sum(:amount).to_f
    end

    field :balance, Float, null: false, description: "Saldo total geral (Saldo das carteiras + Receitas - Despesas)"
    def balance
      require_user!
      user = context[:current_user]
      # Somar Wallet#balance deixaria de fora os lançamentos sem carteira, que
      # ainda assim entram em totalIncome/totalExpense e fariam os três cards do
      # dashboard se contradizerem.
      user.wallets.sum(:initial_balance).to_f +
        user.transactions.income.sum(:amount).to_f - user.transactions.expense.sum(:amount).to_f
    end

    # --- LANÇAMENTOS RECORRENTES ---
    field :recurring_transactions, [ Types::RecurringTransactionType ], null: false,
          description: "Lista os templates recorrentes do usuário autenticado" do
      argument :kind, Types::TransactionKindEnum, required: false, description: "Só receitas ou só despesas"
    end
    def recurring_transactions(kind: nil)
      require_user!
      scope = context[:current_user].recurring_transactions.includes(:wallet)
      scope = scope.where(kind: kind) if kind
      scope.order(day_of_month: :asc, id: :asc)
    end

    field :recurring_transaction, Types::RecurringTransactionType, null: true, description: "Busca um template recorrente do usuário autenticado por ID" do
      argument :id, ID, required: true
    end
    def recurring_transaction(id:)
      require_user!
      context[:current_user].recurring_transactions.find(id)
    rescue ActiveRecord::RecordNotFound
      raise GraphQL::ExecutionError, "Recorrência não encontrada"
    end

    private

    def paginate(scope, limit, offset)
      scope.limit(limit.clamp(1, MAX_PAGE_SIZE)).offset([ offset, 0 ].max)
    end

    def require_user!
      raise GraphQL::ExecutionError, "Você precisa estar autenticado" unless context[:current_user]
    end
  end
end
