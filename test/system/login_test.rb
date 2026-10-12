require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  test "sem sessão, o dashboard manda para o login" do
    visit "/dashboard"

    assert_current_path "/login"
    assert_selector "#loginForm"
  end

  test "senha errada mostra o erro e não entra" do
    visit "/login"
    fill_in "email", with: users(:one).email
    fill_in "password", with: "senha-errada"
    click_button "Entrar"

    assert_text "Email ou senha inválidos"
    assert_current_path "/login"
  end

  test "login correto abre o dashboard com o e-mail do usuário" do
    sign_in users(:one)

    assert_selector "#userEmailDisplay", text: users(:one).email
    assert_selector "h1", text: "Painel Principal"
  end

  test "o JavaScript não consegue ler o cookie de sessão" do
    sign_in users(:one)

    assert_equal "", page.evaluate_script("document.cookie")
    assert_nil page.evaluate_script("localStorage.getItem('token')")
  end

  test "sair encerra a sessão: o dashboard volta a exigir login" do
    sign_in users(:one)
    click_button "Sair"

    assert_current_path "/login"
    visit "/dashboard"
    assert_current_path "/login"
  end

  test "logado, abrir o login ou o cadastro leva direto ao dashboard" do
    sign_in users(:one)

    visit "/login"
    assert_current_path "/dashboard"
    visit "/signup"
    assert_current_path "/dashboard"
  end

  test "o login leva ao cadastro" do
    visit "/login"
    click_link "Cadastre-se"

    assert_current_path "/signup"
  end
end
