require "test_helper"

# CRUD unificado de lançamentos (receita/despesa) e os totais que dependem do tipo.
class TransactionsGraphqlTest < ActiveSupport::TestCase
  def execute(query, variables: {}, user: users(:one))
    AppSchema.execute(query, variables: variables, context: { current_user: user }).to_h
  end

  CREATE = <<~GRAPHQL
    mutation($kind: TransactionKind!, $description: String!, $amount: Float!, $date: ISO8601Date!, $category: String) {
      transactionCreate(kind: $kind, description: $description, amount: $amount, date: $date, category: $category) {
        transaction { id kind description amount date category wallet { id } }
        errors
      }
    }
  GRAPHQL

  setup { Transaction.delete_all }

  # create("kind" => "EXPENSE") ou create({ ... }, user: outro)
  def create(attrs = {}, user: users(:one), **inline)
    vars = { "kind" => "INCOME", "description" => "Salário", "amount" => 100.0, "date" => "2026-08-01" }.merge(attrs, inline)
    execute(CREATE, variables: vars, user: user).dig("data", "transactionCreate")
  end

  # --- criar

  test "cria receita e despesa com o tipo informado" do
    income = create("kind" => "INCOME")
    expense = create("kind" => "EXPENSE", "description" => "Mercado")

    assert_empty income["errors"]
    assert_equal "INCOME", income.dig("transaction", "kind")
    assert_equal "EXPENSE", expense.dig("transaction", "kind")
    assert_equal 1, users(:one).transactions.income.count
    assert_equal 1, users(:one).transactions.expense.count
  end

  test "o lançamento vai para a carteira do usuário, que o cliente não escolhe" do
    created = create

    assert_equal users(:one).wallet.id.to_s, created.dig("transaction", "wallet", "id")
    assert_equal users(:one).wallet, Transaction.find(created.dig("transaction", "id")).wallet
  end

  test "o schema não aceita walletId em lançamentos nem em recorrências" do
    [ 'transactionCreate(kind: INCOME, description: "x", amount: 1, date: "2026-08-01", walletId: "1")',
      'transactionUpdate(id: "1", walletId: "1")',
      'recurringTransactionCreate(kind: INCOME, description: "x", amount: 1, dayOfMonth: 1, startDate: "2026-08-01", walletId: "1")' ].each do |call|
      result = execute("mutation { #{call} { errors } }")

      assert result["errors"].present?, call
    end
    assert_equal 0, Transaction.count
  end

  test "valor inválido volta em errors, sem erro GraphQL" do
    payload = create("amount" => -5.0)

    assert_nil payload["transaction"]
    assert_not_empty payload["errors"]
    assert_equal 0, Transaction.count
  end

  test "valor gigante volta em errors, sem estourar no banco (antes era um erro 500)" do
    payload = create("amount" => 1.0e12)

    assert_nil payload["transaction"]
    assert_match(/menor ou igual a 99999999\.99/, payload["errors"].join)
    assert_equal 0, Transaction.count
  end

  test "tipo inexistente é rejeitado pelo schema" do
    result = execute(CREATE, variables: { "kind" => "TRANSFERENCIA", "description" => "x", "amount" => 1.0, "date" => "2026-08-01" })

    assert result["errors"].present?
    assert_equal 0, Transaction.count
  end

  test "exige autenticação" do
    result = execute(CREATE, variables: { "kind" => "INCOME", "description" => "x", "amount" => 1.0, "date" => "2026-08-01" }, user: nil)

    assert_equal "Você precisa estar autenticado", result["errors"].first["message"]
  end

  # --- atualizar

  UPDATE = <<~GRAPHQL
    mutation($id: ID!, $description: String, $amount: Float) {
      transactionUpdate(id: $id, description: $description, amount: $amount) {
        transaction { description amount kind }
        errors
      }
    }
  GRAPHQL

  test "atualiza campos e preserva o tipo" do
    id = create("kind" => "EXPENSE").dig("transaction", "id")
    payload = execute(UPDATE, variables: { "id" => id, "description" => "Novo", "amount" => 7.5 }).dig("data", "transactionUpdate")

    assert_empty payload["errors"]
    assert_equal "Novo", payload.dig("transaction", "description")
    assert_equal 7.5, payload.dig("transaction", "amount")
    assert_equal "EXPENSE", payload.dig("transaction", "kind")
  end

  test "o tipo não é um argumento de transactionUpdate" do
    result = execute("mutation { transactionUpdate(id: \"1\", kind: INCOME) { errors } }")

    assert result["errors"].present?
  end

  test "um usuário não altera nem enxerga o lançamento de outro" do
    id = create.dig("transaction", "id")

    result = execute(UPDATE, variables: { "id" => id, "description" => "Invasor" }, user: users(:two))
    assert_equal "Lançamento não encontrado", result["errors"].first["message"]
    assert_equal "Salário", Transaction.find(id).description

    read = execute("query($id: ID!) { transaction(id: $id) { id } }", variables: { "id" => id }, user: users(:two))
    assert_equal "Lançamento não encontrado", read["errors"].first["message"]
  end

  # --- excluir

  DELETE = "mutation($id: ID!) { transactionDelete(id: $id) { errors } }".freeze

  test "exclui o próprio lançamento" do
    id = create.dig("transaction", "id")

    assert_difference "Transaction.count", -1 do
      assert_empty execute(DELETE, variables: { "id" => id }).dig("data", "transactionDelete", "errors")
    end
  end

  test "um usuário não exclui o lançamento de outro" do
    id = create.dig("transaction", "id")

    assert_no_difference "Transaction.count" do
      result = execute(DELETE, variables: { "id" => id }, user: users(:two))
      assert_equal "Lançamento não encontrado", result["errors"].first["message"]
    end
  end

  # --- consultas e totais

  test "transactions filtra por tipo e isola por usuário" do
    create("kind" => "INCOME", "description" => "R1")
    create("kind" => "EXPENSE", "description" => "D1")
    create({ "kind" => "INCOME", "description" => "do outro" }, user: users(:two))

    all = execute("{ transactions { description } }").dig("data", "transactions").map { |t| t["description"] }
    incomes = execute("{ transactions(kind: INCOME) { description } }").dig("data", "transactions").map { |t| t["description"] }
    expenses = execute("{ transactions(kind: EXPENSE) { description } }").dig("data", "transactions").map { |t| t["description"] }

    assert_equal %w[D1 R1], all.sort
    assert_equal [ "R1" ], incomes
    assert_equal [ "D1" ], expenses
  end

  test "totalIncome, totalExpense e balance somam cada tipo com o sinal certo" do
    users(:one).wallet.update!(initial_balance: 1000)
    create("kind" => "INCOME", "amount" => 300.0)
    create("kind" => "INCOME", "amount" => 200.0)
    create("kind" => "EXPENSE", "amount" => 150.0)

    data = execute("{ totalIncome totalExpense balance }")["data"]

    assert_equal 500.0, data["totalIncome"]
    assert_equal 150.0, data["totalExpense"]
    assert_equal 1350.0, data["balance"] # 1000 + 500 - 150
  end

  test "uma regra só: o saldo geral é o da carteira, e os totais batem com os dela" do
    users(:one).wallet.update!(initial_balance: 100)
    create("kind" => "INCOME", "amount" => 50.0)
    create("kind" => "EXPENSE", "amount" => 30.0)
    create({ "kind" => "INCOME", "amount" => 999.0 }, user: users(:two)) # de outro usuário: não entra

    data = execute("{ balance totalIncome totalExpense wallet { balance totalIncome totalExpense } }")["data"]

    assert_equal 120.0, data["balance"]
    assert_equal data["balance"], data.dig("wallet", "balance")
    assert_equal data["totalIncome"], data.dig("wallet", "totalIncome")
    assert_equal data["totalExpense"], data.dig("wallet", "totalExpense")
  end

  test "wallet.transactions é paginada e filtrável por tipo" do
    5.times { |i| create({ "description" => "R#{i}" }) }
    create({ "kind" => "EXPENSE", "description" => "D" })

    page = execute("{ wallet { transactions(kind: INCOME, limit: 2, offset: 2) { description } } }")
             .dig("data", "wallet", "transactions")

    assert_equal 2, page.size
  end

  test "excluir a carteira leva os lançamentos e as recorrências dela" do
    wallet = users(:one).wallet
    create
    users(:one).recurring_transactions.create!(kind: :income, description: "S", amount: 1, day_of_month: 1, start_date: Date.new(2026, 8, 1))

    assert_difference [ "Transaction.count", "RecurringTransaction.count" ], -1 do
      wallet.destroy
    end
  end
end
