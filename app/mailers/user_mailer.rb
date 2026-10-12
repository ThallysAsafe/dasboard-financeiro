class UserMailer < ApplicationMailer
  def password_reset(user)
    @user = user
    @url = password_reset_url(token: user.generate_token_for(:password_reset))
    @validade = "30 minutos"

    mail to: user.email, subject: "Redefinir a sua senha"
  end

  def email_confirmation(user)
    @user = user
    @url = email_confirmation_url(token: user.generate_token_for(:email_confirmation))
    @validade = "3 dias"

    mail to: user.email, subject: "Confirme o seu e-mail"
  end
end
