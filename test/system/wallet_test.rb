require "application_system_test_case"

class WalletTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    Transaction.where(user: @user).delete_all
    @user.wallet.update!(name: "Carteira", initial_balance: 100)
    @user.transactions.create!(kind: :income, description: "Salário", amount: 50, date: Date.current)
    sign_in @user
  end

  def open_wallet_modal
    find("[data-action='edit-wallet']").click
    assert_selector "#walletModal.open"
  end

  def save_wallet(name:, initial_balance:)
    fill_in "walletName", with: name
    fill_in "walletInitialBalance", with: initial_balance.to_s
    click_button "walletSubmit"
  end

  test "o cartão da carteira tem o botão de editar" do
    assert_selector "#walletsGrid [data-action='edit-wallet']", text: "Editar carteira"
    assert_no_selector "#walletModal.open"
  end

  test "o formulário abre com o nome e o saldo inicial atuais" do
    open_wallet_modal

    assert_equal "Carteira", find_field("walletName").value
    assert_equal "100", find_field("walletInitialBalance").value
  end

  test "editar nome e saldo inicial atualiza o cartão, o saldo e o banco" do
    assert_money "#balanceValue", "150,00" # 100 inicial + 50 de receita
    open_wallet_modal
    save_wallet(name: "Nubank", initial_balance: 250)

    assert_no_selector "#walletModal.open"
    assert_selector "#walletsGrid .wallet-name", text: "Nubank"
    assert_money "#walletsGrid .wallet-balance", "300,00"
    assert_money "#balanceValue", "300,00"
    assert_text "Carteira atualizada."
    assert_equal "Nubank", @user.wallet.reload.name
    assert_equal 250, @user.wallet.initial_balance
  end

  test "o saldo inicial pode ser negativo (cartão no vermelho)" do
    open_wallet_modal
    save_wallet(name: "Carteira", initial_balance: -80)

    assert_no_selector "#walletModal.open"
    # -80 de saldo inicial + 50 de receita = -30, e o sinal tem de aparecer
    assert_selector "#balanceValue", text: /-[[:space:]]*R\$[[:space:]]*30,00\z/
    assert_selector "#walletsGrid .wallet-balance", text: /-[[:space:]]*R\$[[:space:]]*30,00\z/
    assert_equal(-80, @user.wallet.reload.initial_balance)
  end

  test "nome só com espaços volta como erro do servidor, sem fechar nem salvar" do
    open_wallet_modal
    save_wallet(name: "   ", initial_balance: 500)

    assert_selector "#walletModalAlert", text: "Nome não pode ficar em branco"
    assert_selector "#walletModal.open"
    assert_equal "Carteira", @user.wallet.reload.name
    assert_equal 100, @user.wallet.initial_balance
  end

  test "o navegador barra saldo acima do limite antes de enviar" do
    open_wallet_modal
    save_wallet(name: "Carteira", initial_balance: 100_000_000)

    assert_selector "#walletModal.open"
    assert_equal 100, @user.wallet.reload.initial_balance
  end

  test "fechar sem salvar descarta o que foi digitado" do
    open_wallet_modal
    fill_in "walletName", with: "Rascunho"
    find("[data-action='close-wallet-modal']").click
    assert_no_selector "#walletModal.open"

    open_wallet_modal
    assert_equal "Carteira", find_field("walletName").value
    assert_equal "Carteira", @user.wallet.reload.name
  end

  test "o modal fecha com Esc e clicando fora" do
    open_wallet_modal
    find("body").send_keys(:escape)
    assert_no_selector "#walletModal.open"

    open_wallet_modal
    page.execute_script("document.getElementById('walletModal').click()")
    assert_no_selector "#walletModal.open"
  end

  test "editar a carteira não mexe na de outro usuário" do
    outro = users(:two).wallet.attributes.slice("name", "initial_balance")
    open_wallet_modal
    save_wallet(name: "Só a minha", initial_balance: 7)
    assert_no_selector "#walletModal.open"

    assert_equal outro, users(:two).wallet.reload.attributes.slice("name", "initial_balance")
  end

  test "o modal de lançamento e o de carteira não se atrapalham" do
    open_wallet_modal
    find("[data-action='close-wallet-modal']").click
    first("[data-action='open-create'][data-kind='income']").click

    assert_selector "#entryModal.open"
    assert_no_selector "#walletModal.open"
  end
end
