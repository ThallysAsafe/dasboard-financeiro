class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Dashboard Financeiro <nao-responda@dashboard.local>") }
  layout "mailer"
end
