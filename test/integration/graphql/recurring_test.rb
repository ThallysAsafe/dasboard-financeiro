require "test_helper"

# Executa o schema direto, sem HTTP e sem JWT: o que está sob teste é a camada
# GraphQL, não o transporte.
class RecurringGraphqlTest < ActiveSupport::TestCase
  def execute(query, variables: {}, user: users(:one))
    AppSchema.execute(query, variables: variables, context: { current_user: user }).to_h
  end

  CREATE = <<~GRAPHQL
    mutation($kind: TransactionKind!, $description: String!, $amount: Float!, $dayOfMonth: Int!, $startDate: ISO8601Date!, $endDate: ISO8601Date) {
      recurringTransactionCreate(kind: $kind, description: $description, amount: $amount, dayOfMonth: $dayOfMonth, startDate: $startDate, endDate: $endDate) {
        recurringTransaction { id description dayOfMonth endDate active }
        generatedCount
        errors
      }
    }
  GRAPHQL

  test "cria a recorrência e já materializa os lançamentos atrasados" do
    travel_to Date.new(2026, 8, 9) do
      result = execute(CREATE, variables: {
        "kind" => "INCOME", "description" => "Salário", "amount" => 5000.0,
        "dayOfMonth" => 5, "startDate" => "2026-05-05"
      })
      payload = result.dig("data", "recurringTransactionCreate")

      assert_empty payload["errors"]
      # maio, junho, julho e agosto (dia 5 já passou)
      assert_equal 4, payload["generatedCount"]
      assert_equal 4, users(:one).transactions.income.where.not(recurring_transaction_id: nil).count
    end
  end

  test "syncRecurringEntries não recria o que já existe" do
    travel_to Date.new(2026, 8, 9) do
      execute(CREATE, variables: {
        "kind" => "INCOME", "description" => "Salário", "amount" => 5000.0,
        "dayOfMonth" => 5, "startDate" => "2026-05-05"
      })

      query = "mutation { syncRecurringEntries { createdCount errors } }"
      assert_equal 0, execute(query).dig("data", "syncRecurringEntries", "createdCount")
    end
  end

  test "exige autenticação" do
    result = execute("mutation { syncRecurringEntries { createdCount errors } }", user: nil)

    assert_equal "Você precisa estar autenticado", result["errors"].first["message"]
  end

  test "endDate explicitamente nulo limpa o prazo final" do
    travel_to Date.new(2026, 8, 9) do
      id = execute(CREATE, variables: {
        "kind" => "INCOME", "description" => "Salário", "amount" => 5000.0, "dayOfMonth" => 5,
        "startDate" => "2026-05-05", "endDate" => "2026-06-30"
      }).dig("data", "recurringTransactionCreate", "recurringTransaction", "id")

      update = <<~GRAPHQL
        mutation($id: ID!, $endDate: ISO8601Date) {
          recurringTransactionUpdate(id: $id, endDate: $endDate) {
            recurringTransaction { endDate }
            generatedCount
            errors
          }
        }
      GRAPHQL
      payload = execute(update, variables: { "id" => id, "endDate" => nil })
                  .dig("data", "recurringTransactionUpdate")

      assert_empty payload["errors"]
      assert_nil payload.dig("recurringTransaction", "endDate")
      # Sem prazo, julho e agosto passam a ser devidos.
      assert_equal 2, payload["generatedCount"]
    end
  end

  test "pausar impede novas gerações" do
    id = nil

    travel_to Date.new(2026, 8, 9) do
      id = execute(CREATE, variables: {
        "kind" => "INCOME", "description" => "Salário", "amount" => 5000.0,
        "dayOfMonth" => 5, "startDate" => "2026-08-05"
      }).dig("data", "recurringTransactionCreate", "recurringTransaction", "id")

      pause = <<~GRAPHQL
        mutation($id: ID!) {
          recurringTransactionUpdate(id: $id, active: false) {
            recurringTransaction { active }
            errors
          }
        }
      GRAPHQL
      assert_equal false, execute(pause, variables: { "id" => id })
        .dig("data", "recurringTransactionUpdate", "recurringTransaction", "active")
    end

    # Quatro meses depois, o template pausado segue sem gerar nada.
    travel_to Date.new(2026, 12, 31) do
      sync = "mutation { syncRecurringEntries { createdCount } }"
      assert_equal 0, execute(sync).dig("data", "syncRecurringEntries", "createdCount")
    end
  end

  test "um usuário não apaga a recorrência de outro" do
    id = execute(CREATE, variables: {
      "kind" => "INCOME", "description" => "Salário", "amount" => 5000.0,
      "dayOfMonth" => 5, "startDate" => "2026-08-05"
    }).dig("data", "recurringTransactionCreate", "recurringTransaction", "id")

    delete = "mutation($id: ID!) { recurringTransactionDelete(id: $id) { errors } }"
    result = execute(delete, variables: { "id" => id }, user: users(:two))

    assert_equal "Recorrência não encontrada", result["errors"].first["message"]
    assert_equal 1, users(:one).recurring_transactions.count
  end

  test "apagar a recorrência preserva os lançamentos gerados" do
    travel_to Date.new(2026, 8, 9) do
      id = execute(CREATE, variables: {
        "kind" => "INCOME", "description" => "Salário", "amount" => 5000.0,
        "dayOfMonth" => 5, "startDate" => "2026-06-05"
      }).dig("data", "recurringTransactionCreate", "recurringTransaction", "id")

      delete = "mutation($id: ID!) { recurringTransactionDelete(id: $id) { errors } }"
      assert_empty execute(delete, variables: { "id" => id }).dig("data", "recurringTransactionDelete", "errors")

      assert_equal 3, users(:one).transactions.income.where(description: "Salário").count
      assert_equal 0, users(:one).recurring_transactions.count
    end
  end
end
