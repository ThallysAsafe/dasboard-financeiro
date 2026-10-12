require "test_helper"

# CRUD unificado de lançamentos (receita/despesa) e os totais que dependem do tipo.
class TransactionsGraphqlTest < ActiveSupport::TestCase
  def execute(query, variables: {}, user: users(:one))
    AppSchema.execute(query, variables: variables, context: { current_user: user }).to_h
  end

  CREATE = <<~GRAPHQL
    mutation($kind: TransactionKind!, $description: String!, $amount: Float!, $date: ISO8601Date!, $category: String, $walletId: ID) {
      transactionCreate(kind: $kind, description: $description, amount: $amount, date: $date, category: $category, walletId: $walletId) {
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

  test "sem carteira informada usa a primeira do usuário" do
    created = create

    assert_equal users(:one).wallets.first.id.to_s, created.dig("transaction", "wallet", "id")
  end

  test "valor inválido volta em errors, sem erro GraphQL" do
    payload = create("amount" => -5.0)

    assert_nil payload["transaction"]
    assert_not_empty payload["errors"]
    assert_equal 0, Transaction.count
  end

  test "tipo inexistente é rejeitado pelo schema" do
    result = execute(CREATE, variables: { "kind" => "TRANSFERENCIA", "description" => "x", "amount" => 1.0, "date" => "2026-08-01" })

    assert result["errors"].present?
    assert_equal 0, Transaction.count
  end

  test "não usa a carteira de outro usuário" do
    other_wallet = users(:two).wallets.create!(name: "Alheia", initial_balance: 0)
    result = execute(CREATE, variables: { "kind" => "INCOME", "description" => "x", "amount" => 1.0,
                                          "date" => "2026-08-01", "walletId" => other_wallet.id.to_s })

    assert_equal "Carteira não encontrada", result["errors"].first["message"]
    assert_equal 0, Transaction.count
  end

  test "exige autenticação" do
    result = execute(CREATE, variables: { "kind" => "INCOME", "description" => "x", "amount" => 1.0, "date" => "2026-08-01" }, user: nil)

    assert_equal "Você precisa estar autenticado", result["errors"].first["message"]
  end

  # --- atualizar

  UPDATE = <<~GRAPHQL
    mutation($id: ID!, $description: String, $amount: Float, $walletId: ID) {
      transactionUpdate(id: $id, description: $description, amount: $amount, walletId: $walletId) {
        transaction { description amount kind wallet { id } }
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

  test "walletId nulo explícito tira a carteira; ausente mantém" do
    id = create.dig("transaction", "id")

    kept = execute(UPDATE, variables: { "id" => id, "description" => "Só descrição" }).dig("data", "transactionUpdate")
    assert_not_nil kept.dig("transaction", "wallet")

    cleared = execute(UPDATE, variables: { "id" => id, "walletId" => nil }).dig("data", "transactionUpdate")
    assert_nil cleared.dig("transaction", "wallet")
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
    users(:one).wallets.destroy_all
    users(:one).wallets.create!(name: "A", initial_balance: 1000)
    create("kind" => "INCOME", "amount" => 300.0)
    create("kind" => "INCOME", "amount" => 200.0)
    create("kind" => "EXPENSE", "amount" => 150.0)

    data = execute("{ totalIncome totalExpense balance }")["data"]

    assert_equal 500.0, data["totalIncome"]
    assert_equal 150.0, data["totalExpense"]
    assert_equal 1350.0, data["balance"] # 1000 + 500 - 150
  end

  test "o saldo conta lançamentos sem carteira, e o da carteira só os dela" do
    users(:one).wallets.destroy_all
    wallet = users(:one).wallets.create!(name: "A", initial_balance: 100)
    create({ "kind" => "INCOME", "amount" => 50.0, "walletId" => wallet.id.to_s })
    users(:one).transactions.create!(kind: :income, description: "solto", amount: 10, date: Date.new(2026, 8, 1))

    data = execute("{ balance wallets { balance totalIncome totalExpense } }")["data"]

    assert_equal 160.0, data["balance"]
    assert_equal 150.0, data["wallets"].first["balance"]
    assert_equal 50.0, data["wallets"].first["totalIncome"]
  end

  test "wallet.transactions é paginada e filtrável por tipo" do
    wallet = users(:one).wallets.first || users(:one).wallets.create!(name: "A", initial_balance: 0)
    5.times { |i| create({ "description" => "R#{i}", "walletId" => wallet.id.to_s }) }
    create({ "kind" => "EXPENSE", "description" => "D", "walletId" => wallet.id.to_s })

    page = execute("query($id: ID!) { wallet(id: $id) { transactions(kind: INCOME, limit: 2, offset: 2) { description } } }",
                   variables: { "id" => wallet.id.to_s }).dig("data", "wallet", "transactions")

    assert_equal 2, page.size
  end

  test "excluir a carteira exclui os lançamentos dela" do
    wallet = users(:one).wallets.create!(name: "Temporária", initial_balance: 0)
    create({ "walletId" => wallet.id.to_s })

    assert_difference "Transaction.count", -1 do
      wallet.destroy
    end
  end
end
