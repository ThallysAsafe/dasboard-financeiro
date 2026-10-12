require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    # Estado conhecido: carteira com 100 e nenhum lançamento (os fixtures trazem alguns).
    Transaction.where(user: @user).delete_all
    @user.wallet.update!(initial_balance: 100)
  end

  def open_form(kind)
    first("[data-action='open-create'][data-kind='#{kind}']").click
    assert_selector "#entryModal.open"
  end

  def save_entry(description:, amount:)
    fill_in "entryDescription", with: description
    fill_in "entryAmount", with: amount.to_s
    click_button "entrySubmit"
    assert_no_selector "#entryModal.open"
  end

  def create_entry(kind, description, amount)
    open_form(kind)
    save_entry(description: description, amount: amount)
  end

  # --- leitura

  test "mostra o saldo, os totais e a carteira" do
    sign_in @user

    assert_money "#balanceValue", "100,00"
    assert_money "#incomeValue", "0,00"
    assert_money "#expenseValue", "0,00"
    assert_selector "#walletsGrid .wallet-name", text: @user.wallet.name
    assert_text "Nenhuma receita cadastrada ainda."
    assert_text "Nenhuma despesa cadastrada ainda."
  end

  test "lista os lançamentos existentes, o mais recente primeiro" do
    @user.transactions.create!(kind: :income, description: "Antiga", amount: 10, date: Date.current - 5)
    @user.transactions.create!(kind: :income, description: "Recente", amount: 20, date: Date.current)
    sign_in @user

    rows = all("#incomesList .entry-row").map(&:text)
    assert_equal 2, rows.size
    assert_match(/Recente/, rows.first)
    assert_match(/Antiga/, rows.last)
  end

  test "mostra só os dados do próprio usuário" do
    users(:two).transactions.create!(kind: :income, description: "Do outro usuário", amount: 999, date: Date.current)
    sign_in @user

    assert_no_text "Do outro usuário"
    assert_money "#incomeValue", "0,00"
  end

  # --- criar

  test "criar uma receita atualiza a lista, os totais e o saldo" do
    sign_in @user
    create_entry("income", "Salário", 1000)

    assert_selector "#incomesList .entry-row", count: 1, text: "Salário"
    assert_money "#incomeValue", "1.000,00"
    assert_money "#balanceValue", "1.100,00"
    assert_money "#walletsGrid .wallet-balance", "1.100,00"
    assert_text "Lançamento salvo com sucesso."
  end

  test "criar uma despesa diminui o saldo" do
    sign_in @user
    create_entry("expense", "Mercado", 40)

    assert_selector "#expensesList .entry-row", count: 1, text: "Mercado"
    assert_money "#expenseValue", "40,00"
    assert_money "#balanceValue", "60,00"
  end

  test "o navegador barra valor zero antes de enviar" do
    sign_in @user
    open_form("income")
    fill_in "entryDescription", with: "Zero"
    fill_in "entryAmount", with: "0"
    click_button "entrySubmit"

    assert_selector "#entryModal.open"
    assert_equal 0, @user.transactions.count
  end

  test "o formulário mostra o erro do servidor em português" do
    sign_in @user
    open_form("income")
    fill_in "entryDescription", with: "   " # passa no navegador, mas o JS apara e o servidor recusa
    fill_in "entryAmount", with: "10"
    click_button "entrySubmit"

    assert_selector "#modalAlert", text: "Descrição não pode ficar em branco"
    assert_selector "#entryModal.open"
    assert_equal 0, @user.transactions.count
  end

  test "a categoria aparece no lançamento" do
    sign_in @user
    open_form("income")
    fill_in "entryDescription", with: "Freela"
    fill_in "entryAmount", with: "50"
    fill_in "entryCategory", with: "Trabalho"
    click_button "entrySubmit"

    assert_selector "#incomesList .entry-row", text: /Freela.*Trabalho/m
  end

  # --- modal

  test "o modal fecha pelo X, pelo Esc e clicando fora" do
    sign_in @user

    open_form("income")
    find("[data-action='close-modal']").click
    assert_no_selector "#entryModal.open"

    open_form("income")
    find("body").send_keys(:escape)
    assert_no_selector "#entryModal.open"

    open_form("expense")
    page.execute_script("document.getElementById('entryModal').click()")
    assert_no_selector "#entryModal.open"
  end

  # --- editar e excluir

  test "editar um lançamento atualiza o valor e o saldo" do
    sign_in @user
    create_entry("income", "Salário", 1000)

    find("#incomesList [data-action='edit']").click
    assert_selector "#entryModal.open"
    assert_equal "Salário", find_field("entryDescription").value
    fill_in "entryAmount", with: "1500"
    click_button "entrySubmit"

    assert_no_selector "#entryModal.open"
    assert_money "#balanceValue", "1.600,00"
  end

  test "excluir pede confirmação; cancelar mantém" do
    sign_in @user
    create_entry("expense", "Mercado", 40)

    dismiss_confirm { find("#expensesList [data-action='delete']").click }

    assert_selector "#expensesList .entry-row", count: 1
    assert_equal 1, @user.transactions.expense.count
  end

  test "excluir confirmando remove o lançamento e devolve o saldo" do
    sign_in @user
    create_entry("expense", "Mercado", 40)
    assert_money "#balanceValue", "60,00"

    accept_confirm { find("#expensesList [data-action='delete']").click }

    assert_text "Nenhuma despesa cadastrada ainda."
    assert_money "#balanceValue", "100,00"
    assert_equal 0, @user.transactions.count
  end

  # --- recorrência

  def create_recurring(kind, description, amount, day:, start:)
    open_form(kind)
    fill_in "entryDescription", with: description
    fill_in "entryAmount", with: amount.to_s
    check "entryRecurring"
    fill_in "entryDayOfMonth", with: day.to_s
    set_date("entryDate", start)
    click_button "entrySubmit"
    assert_no_selector "#entryModal.open"
  end

  test "criar recorrência gera os lançamentos devidos e lista o template" do
    sign_in @user
    create_recurring("income", "Salário mensal", 1000, day: 1, start: Date.current.beginning_of_month - 2.months)

    assert_selector "#recurringList .entry-row", count: 1, text: "Salário mensal"
    assert_selector "#incomesList .entry-row", count: 3 # há 2 meses, mês passado e este (dia 1 já passou)
    assert_selector "#incomesList .badge-recurring", count: 3
    assert_money "#balanceValue", "3.100,00"
    assert_text(/3 lançamentos gerados/)
  end

  test "pausar e retomar a recorrência" do
    sign_in @user
    create_recurring("income", "Salário mensal", 1000, day: 1, start: Date.current.beginning_of_month)

    find("#recurringList [data-action='toggle-recurring']").click
    assert_selector "#recurringList [data-action='toggle-recurring']", text: "Retomar"
    assert_not @user.recurring_transactions.first.active?

    find("#recurringList [data-action='toggle-recurring']").click
    assert_selector "#recurringList [data-action='toggle-recurring']", text: "Pausar"
    assert @user.recurring_transactions.first.active?
  end

  test "excluir a recorrência mantém os lançamentos já gerados" do
    sign_in @user
    create_recurring("income", "Salário mensal", 1000, day: 1, start: Date.current.beginning_of_month - 1.month)
    assert_selector "#incomesList .entry-row", count: 2

    accept_confirm { find("#recurringList [data-action='delete-recurring']").click }

    assert_no_selector "#recurringList .entry-row"
    assert_selector "#incomesList .entry-row", count: 2
    assert_money "#balanceValue", "2.100,00"
  end

  test "editar a recorrência abre o formulário com os dados do template" do
    sign_in @user
    create_recurring("expense", "Aluguel", 800, day: 5, start: Date.current.beginning_of_month)

    find("#recurringList [data-action='edit-recurring']").click

    assert_selector "#entryModal.open"
    assert_equal "Aluguel", find_field("entryDescription").value
    assert_equal "5", find_field("entryDayOfMonth").value
    assert find_field("entryRecurring", disabled: :all).checked?
  end

  # --- paginação

  test "Carregar mais traz a página seguinte e some quando acaba" do
    105.times { |i| @user.transactions.create!(kind: :income, description: "Receita #{i}", amount: 1, date: Date.current - i) }
    sign_in @user

    assert_selector "#incomesList .entry-row", count: 100
    click_button "Carregar mais"

    assert_selector "#incomesList .entry-row", count: 105
    assert_no_button "Carregar mais"
    assert_money "#incomeValue", "105,00" # os totais sempre cobriram tudo
  end
end
