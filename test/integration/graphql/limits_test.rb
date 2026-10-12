require "test_helper"

# Proteções do schema: profundidade, complexidade, paginação e N+1.
class GraphqlLimitsTest < ActiveSupport::TestCase
  # Espelha DASHBOARD_QUERY de dashboard/_scripts.js.erb.
  DASHBOARD = <<~GRAPHQL
    query Dashboard($limit: Int!) {
      balance totalIncome totalExpense
      wallets { id name balance totalIncome totalExpense }
      incomes: transactions(kind: INCOME, limit: $limit) { id description amount date category recurringTransactionId wallet { id name } }
      expenses: transactions(kind: EXPENSE, limit: $limit) { id description amount date category recurringTransactionId wallet { id name } }
      recurringIncomes: recurringTransactions(kind: INCOME) { id description amount dayOfMonth startDate endDate category active nextOccurrence wallet { id name } }
      recurringExpenses: recurringTransactions(kind: EXPENSE) { id description amount dayOfMonth startDate endDate category active nextOccurrence wallet { id name } }
    }
  GRAPHQL

  # Os fixtures criam lançamentos por usuário e bagunçariam as contagens.
  setup do
    Transaction.delete_all
  end

  def execute(query, variables: {}, user: users(:one))
    AppSchema.execute(query, variables: variables, context: { current_user: user }).to_h
  end

  def seed(user, count, wallet: nil)
    wallet ||= user.wallets.create!(name: "Carteira", initial_balance: 0)
    count.times do |i|
      user.transactions.create!(kind: :income, description: "Receita #{i}", amount: 10, date: Date.new(2026, 1, 1) + i, wallet: wallet)
    end
    wallet
  end

  def count_selects(&block)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].start_with?("SELECT") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    queries.size
  end

  test "a query do dashboard continua dentro dos limites" do
    seed(users(:one), 3)
    result = execute(DASHBOARD, variables: { "limit" => 100 })

    assert_nil result["errors"]
    assert_equal 3, result.dig("data", "incomes").size
  end

  test "query que explora o ciclo wallet -> transactions -> wallet é rejeitada por profundidade" do
    seed(users(:one), 1)
    nested = "id"
    6.times { nested = "wallet { transactions { #{nested} } }" }
    result = execute("{ wallets { transactions { #{nested} } } }")

    assert_match(/depth/i, result["errors"].first["message"])
    assert_nil result["data"]
  end

  test "introspecção (GraphiQL) não é barrada pelo limite de profundidade" do
    result = execute(GraphQL::Introspection::INTROSPECTION_QUERY)

    assert_nil result["errors"]
  end

  test "transactions devolve no máximo 100 por padrão, da mais recente para a mais antiga" do
    seed(users(:one), 120)
    list = execute("{ transactions(kind: INCOME) { date } }").dig("data", "transactions")

    assert_equal 100, list.size
    assert_equal list.map { |i| i["date"] }.sort.reverse, list.map { |i| i["date"] }
    assert_equal "2026-04-30", list.first["date"]
  end

  test "offset pega a página seguinte sem repetir nem pular itens" do
    seed(users(:one), 12)
    first = execute("{ transactions(kind: INCOME, limit: 5) { description } }").dig("data", "transactions")
    second = execute("{ transactions(kind: INCOME, limit: 5, offset: 5) { description } }").dig("data", "transactions")
    third = execute("{ transactions(kind: INCOME, limit: 5, offset: 10) { description } }").dig("data", "transactions")

    all = (first + second + third).map { |i| i["description"] }
    assert_equal 12, all.uniq.size
    assert_equal 2, third.size
  end

  test "limit acima do máximo é reduzido para 500 e valores inválidos são saneados" do
    seed(users(:one), 3)

    assert_equal 3, execute("{ transactions(limit: 100000) { id } }").dig("data", "transactions").size
    assert_equal 1, execute("{ transactions(limit: 0) { id } }").dig("data", "transactions").size
    assert_equal 3, execute("{ transactions(limit: 10, offset: -5) { id } }").dig("data", "transactions").size
  end

  test "o filtro por kind também é paginado" do
    user = users(:one)
    8.times { |i| user.transactions.create!(kind: :expense, description: "D#{i}", amount: 5, date: Date.new(2026, 2, 1) + i) }

    assert_equal 3, execute("{ transactions(kind: EXPENSE, limit: 3) { id } }").dig("data", "transactions").size
  end

  test "paginação continua restrita aos dados do próprio usuário" do
    seed(users(:two), 5)

    assert_empty execute("{ transactions { id } }").dig("data", "transactions")
  end

  test "número de SELECTs não cresce com a quantidade de lançamentos (sem N+1)" do
    user = users(:one)
    seed(user, 2)
    query = "{ transactions { id wallet { id name } user { id email } } }"
    few = count_selects { execute(query) }

    seed(user, 40)
    many = count_selects { execute(query) }

    assert_equal few, many
  end
end
