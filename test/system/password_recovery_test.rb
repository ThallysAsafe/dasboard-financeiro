require "application_system_test_case"

class PasswordRecoveryTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  NOVA = "novasenha1234".freeze

  setup do
    ActionMailer::Base.deliveries.clear
    @user = users(:one)
  end

  # Espera a resposta aparecer antes de devolver: o pedido roda numa thread do servidor, e se
  # o bloco perform_enqueued_jobs do teste fechasse antes disso, o e-mail entraria na fila
  # depois e nunca seria entregue.
  def pedir_link(email = @user.email)
    visit "/password/forgot"
    fill_in "email", with: email
    click_button "Enviar link"
    assert_text "Se existir uma conta com este e-mail"
  end

  # O e-mail usa o host de teste (www.example.com); aqui só importa o caminho e o token.
  def link_do_ultimo_email
    link = ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{https?://\S+}]
    uri = URI.parse(link)
    "#{uri.path}?#{uri.query}"
  end

  def definir_senha(senha, confirmacao = senha)
    fill_in "password", with: senha
    fill_in "passwordConfirmation", with: confirmacao
    click_button "Salvar nova senha"
  end

  test "o login leva à recuperação de senha" do
    visit "/login"
    click_link "Esqueceu sua senha?"

    assert_current_path "/password/forgot"
    assert_selector "#forgotForm"
  end

  test "fluxo completo: pedir o link, receber o e-mail, escolher a nova senha e entrar com ela" do
    perform_enqueued_jobs do
      pedir_link
      assert_text "Se existir uma conta com este e-mail"
    end
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal [ @user.email ], ActionMailer::Base.deliveries.last.to

    visit link_do_ultimo_email
    assert_selector "#resetForm"
    definir_senha(NOVA)

    assert_text "Senha alterada"
    click_link "Ir para o login"
    sign_in @user, password: NOVA
    assert_selector "#userEmailDisplay", text: @user.email
  end

  test "depois de trocar, a senha antiga não entra mais" do
    perform_enqueued_jobs { pedir_link }
    visit link_do_ultimo_email
    definir_senha(NOVA)
    assert_text "Senha alterada"

    visit "/login"
    fill_in "email", with: @user.email
    fill_in "password", with: "123456"
    click_button "Entrar"

    assert_text "Email ou senha inválidos"
    assert_current_path "/login"
  end

  test "o token sai da barra de endereço assim que a página o lê" do
    perform_enqueued_jobs { pedir_link }
    visit link_do_ultimo_email

    assert_selector "#resetForm"
    assert_no_match(/token/, page.current_url)
    assert_equal "/password/reset", URI.parse(page.current_url).request_uri
  end

  test "o link vale uma vez só: usar de novo mostra que está inválido" do
    perform_enqueued_jobs { pedir_link }
    link = link_do_ultimo_email
    visit link
    definir_senha(NOVA)
    assert_text "Senha alterada"

    visit link
    definir_senha("outrasenha9999")

    assert_text "Link inválido ou expirado"
    assert_link "Pedir um novo link"
  end

  test "e-mail que não existe recebe a mesma mensagem e nenhum e-mail sai" do
    perform_enqueued_jobs do
      pedir_link("ninguem@exemplo.com")

      assert_text "Se existir uma conta com este e-mail"
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "pedir o link sem e-mail mostra um aviso e não chama o servidor" do
    visit "/password/forgot"
    click_button "Enviar link"

    assert_text "Informe o e-mail da sua conta."
    assert_empty ActionMailer::Base.deliveries
  end

  test "senhas diferentes são barradas na tela" do
    perform_enqueued_jobs { pedir_link }
    visit link_do_ultimo_email
    definir_senha(NOVA, "diferente12345")

    assert_text "As senhas não conferem."
    assert User.authenticate_with(@user.email, "123456"), "a senha não mudou"
  end

  test "senha curta volta com a mensagem do servidor e deixa tentar de novo no mesmo link" do
    perform_enqueued_jobs { pedir_link }
    visit link_do_ultimo_email
    definir_senha("curta1")

    assert_text "Senha é muito curto (mínimo: 10 caracteres)"
    assert_selector "#resetForm"

    definir_senha(NOVA)
    assert_text "Senha alterada"
  end

  test "abrir a página de nova senha sem o token mostra o link inválido" do
    visit "/password/reset"

    assert_text "Link inválido. Peça um novo."
    assert_link "Pedir um novo link"
    assert_no_selector "#resetForm", visible: :visible
  end

  test "um token adulterado é recusado" do
    visit "/password/reset?token=lixo"
    definir_senha(NOVA)

    assert_text "Link inválido ou expirado"
    assert User.authenticate_with(@user.email, "123456")
  end
end
