require "test_helper"

class ApplicationMailerTest < ActionMailer::TestCase
  class ExemploMailer < ApplicationMailer
    def ola
      mail(to: "alguem@exemplo.com", subject: "Olá") { |format| format.text { render plain: "oi" } }
    end
  end

  test "o remetente padrão vem do ambiente, com um valor de desenvolvimento por omissão" do
    mail = ExemploMailer.ola

    assert_equal [ "nao-responda@dashboard.local" ], mail.from
    assert_match(/Dashboard Financeiro/, mail[:from].to_s)
  end

  test "MAIL_FROM troca o remetente sem mexer no código" do
    original = ENV["MAIL_FROM"]
    ENV["MAIL_FROM"] = "App <ola@meudominio.com>"

    assert_equal [ "ola@meudominio.com" ], ExemploMailer.ola.from
  ensure
    original ? ENV["MAIL_FROM"] = original : ENV.delete("MAIL_FROM")
  end

  test "nos testes nada é enviado de verdade: o envio é :test e vai para deliveries" do
    assert_equal :test, ActionMailer::Base.delivery_method

    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      ExemploMailer.ola.deliver_now
    end
  end

  test "os links dos e-mails têm uma base configurada" do
    assert ActionMailer::Base.default_url_options[:host].present?
  end
end
