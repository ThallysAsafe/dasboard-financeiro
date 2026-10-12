require "application_system_test_case"

class EmailConfirmationTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  SENHA = "senhaforte123".freeze

  setup do
    ActionMailer::Base.deliveries.clear
    @user = users(:one)
  end

  def link_do_ultimo_email
    link = ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{https?://\S+}]
    uri = URI.parse(link)
    "#{uri.path}?#{uri.query}"
  end

  # --- o aviso no painel

  test "quem ainda não confirmou vê o aviso com o e-mail e o botão de reenviar" do
    sign_in @user

    assert_selector "#confirmBanner", visible: :visible
    assert_selector "#confirmBannerEmail", text: @user.email
    assert_button "Reenviar e-mail"
  end

  test "quem já confirmou não vê o aviso" do
    @user.confirm_email!
    sign_in @user

    assert_selector "#confirmBanner", visible: :hidden
  end

  test "o aviso não bloqueia o uso do painel" do
    sign_in @user

    assert_selector "#confirmBanner", visible: :visible
    first("[data-action='open-create'][data-kind='income']").click
    assert_selector "#entryModal.open"
  end

  # --- reenviar

  test "reenviar manda o e-mail e confirma na tela" do
    perform_enqueued_jobs do
      sign_in @user
      click_button "Reenviar e-mail"

      assert_text "Enviamos um novo link para #{@user.email}."
    end
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal [ @user.email ], ActionMailer::Base.deliveries.last.to
    assert_equal "Confirme o seu e-mail", ActionMailer::Base.deliveries.last.subject
  end

  # --- confirmar

  test "fluxo completo: cadastrar, receber o e-mail, abrir o link e o aviso some" do
    perform_enqueued_jobs do
      visit "/signup"
      fill_in "email", with: "novo@exemplo.com"
      fill_in "password", with: SENHA
      fill_in "passwordConfirmation", with: SENHA
      click_button "Criar conta"
      assert_dashboard_ready("novo@exemplo.com")
    end
    assert_selector "#confirmBanner", visible: :visible
    assert_equal 1, ActionMailer::Base.deliveries.size, "o cadastro envia a confirmação"

    visit link_do_ultimo_email
    assert_text "Tudo certo!"
    assert_text "E-mail confirmado."
    assert User.find_by(email: "novo@exemplo.com").email_confirmed?

    visit "/dashboard"
    assert_dashboard_ready("novo@exemplo.com")
    assert_selector "#confirmBanner", visible: :hidden
  end

  test "o token sai da barra de endereço ao abrir o link" do
    token = @user.generate_token_for(:email_confirmation)
    visit "/email/confirm?token=#{token}"

    assert_text "Tudo certo!"
    assert_no_match(/token/, page.current_url)
  end

  test "link inválido mostra o erro e não confirma ninguém" do
    visit "/email/confirm?token=lixo"

    assert_text "Não foi possível confirmar"
    assert_text "Link inválido ou expirado"
    assert_not @user.reload.email_confirmed?
  end

  test "sem o token mostra o erro" do
    visit "/email/confirm"

    assert_text "Não foi possível confirmar"
    assert_text "Link inválido"
  end

  test "um link de redefinição de senha não confirma o e-mail" do
    visit "/email/confirm?token=#{@user.generate_token_for(:password_reset)}"

    assert_text "Não foi possível confirmar"
    assert_not @user.reload.email_confirmed?
  end

  test "o link antigo deixa de valer depois de trocar o e-mail" do
    token = @user.generate_token_for(:email_confirmation)
    @user.update!(email: "trocado@exemplo.com")

    visit "/email/confirm?token=#{token}"

    assert_text "Não foi possível confirmar"
    assert_not @user.reload.email_confirmed?
  end
end
