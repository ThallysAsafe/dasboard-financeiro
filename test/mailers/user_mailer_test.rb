require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  def corpo(mail)
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].join("\n")
  end

  def link_do(mail, parte)
    mail.public_send(parte).body.decoded[%r{https?://\S+?(?=["<\s])}]
  end

  # --- redefinição de senha

  test "o e-mail de redefinição vai para o dono da conta, em português" do
    mail = UserMailer.password_reset(users(:one))

    assert_equal [ users(:one).email ], mail.to
    assert_equal "Redefinir a sua senha", mail.subject
    assert_match(/Redefinir a sua senha/, corpo(mail))
    assert_match(/30 minutos/, corpo(mail))
    assert_match(/uma vez/, corpo(mail))
  end

  test "tem versão em texto e em HTML" do
    mail = UserMailer.password_reset(users(:one))

    assert_equal 2, mail.parts.size
    assert mail.text_part
    assert mail.html_part
  end

  test "o link do e-mail leva ao formulário e o token resolve para o usuário certo" do
    mail = UserMailer.password_reset(users(:one))

    %i[text_part html_part].each do |parte|
      link = link_do(mail, parte)
      uri = URI.parse(link)
      token = Rack::Utils.parse_query(uri.query)["token"]

      assert_equal "/password/reset", uri.path, parte
      assert_equal users(:one), User.find_by_token_for(:password_reset, token), parte
    end
  end

  test "nunca coloca a senha nem o hash no e-mail" do
    user = users(:one)
    mail = UserMailer.password_reset(user)

    assert_no_match(/123456/, corpo(mail))
    assert_not_includes corpo(mail), user.password_digest
  end

  # --- confirmação de e-mail

  test "o e-mail de confirmação tem o link com um token de confirmação válido" do
    mail = UserMailer.email_confirmation(users(:two))

    assert_equal [ users(:two).email ], mail.to
    assert_equal "Confirme o seu e-mail", mail.subject
    link = link_do(mail, :text_part)
    uri = URI.parse(link)
    token = Rack::Utils.parse_query(uri.query)["token"]

    assert_equal "/email/confirm", uri.path
    assert_equal users(:two), User.find_by_token_for(:email_confirmation, token)
    assert_nil User.find_by_token_for(:password_reset, token), "não pode servir para redefinir a senha"
  end

  test "o botão do HTML e o texto apontam para o mesmo link" do
    mail = UserMailer.email_confirmation(users(:one))

    assert_equal link_do(mail, :text_part), link_do(mail, :html_part)
  end
end
