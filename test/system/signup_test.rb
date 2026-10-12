require "application_system_test_case"

class SignupTest < ApplicationSystemTestCase
  SENHA = "senhaforte123".freeze

  def fill_signup(email: "novo@exemplo.com", password: SENHA, confirmation: SENHA)
    visit "/signup"
    fill_in "email", with: email
    fill_in "password", with: password
    fill_in "passwordConfirmation", with: confirmation
    click_button "Criar conta"
  end

  test "cadastro válido cria a conta, a carteira e já abre o dashboard" do
    assert_difference [ "User.count", "Wallet.count" ], 1 do
      fill_signup
      assert_current_path "/dashboard"
    end

    assert_selector "#userEmailDisplay", text: "novo@exemplo.com"
    assert_selector "#walletsGrid .wallet-name", text: User::DEFAULT_WALLET_NAME
    assert_money "#walletsGrid .wallet-balance", "0,00"
  end

  test "senhas diferentes são barradas no navegador, sem chamar o servidor" do
    assert_no_difference "User.count" do
      fill_signup(confirmation: "outrasenha123")
      assert_text "As senhas não conferem."
    end
    assert_current_path "/signup"
  end

  test "senha curta mostra o erro do servidor em português" do
    assert_no_difference "User.count" do
      fill_signup(password: "curta1", confirmation: "curta1")
      assert_text "Senha é muito curto (mínimo: 10 caracteres)"
    end
  end

  test "e-mail já cadastrado" do
    assert_no_difference "User.count" do
      fill_signup(email: users(:one).email)
      assert_text "E-mail já está em uso"
    end
  end

  test "e-mail inválido" do
    fill_signup(email: "sem-arroba")

    assert_text "E-mail não é válido"
    assert_current_path "/signup"
  end

  test "o cadastro leva ao login" do
    visit "/signup"
    click_link "Entrar"

    assert_current_path "/login"
  end

  test "depois de cadastrar, sair e entrar de novo funciona" do
    fill_signup
    assert_dashboard_ready("novo@exemplo.com")
    click_button "Sair"
    assert_current_path "/login"

    fill_in "email", with: "novo@exemplo.com"
    fill_in "password", with: SENHA
    click_button "Entrar"
    assert_dashboard_ready("novo@exemplo.com")
  end
end
