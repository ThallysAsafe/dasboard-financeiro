require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # CHROME_BIN / CHROMEDRIVER_PATH existem no container de desenvolvimento
  # (Dockerfile.dev); no CI o Chrome vem do runner e o Selenium acha sozinho.
  Selenium::WebDriver::Chrome::Service.driver_path = ENV["CHROMEDRIVER_PATH"] if ENV["CHROMEDRIVER_PATH"]

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
    options.add_argument("--no-sandbox")            # roda como root no container
    options.add_argument("--disable-dev-shm-usage") # /dev/shm pequeno no Docker
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
  end

  setup do
    Capybara.default_max_wait_time = 5
    # O login/cadastro têm limite por IP; a suíte inteira sai de 127.0.0.1.
    Rack::Attack.cache.store.clear
  end

  # Violações de CSP e exceções de JS não podem passar despercebidas: o app serve
  # todo o JS por arquivos sob uma CSP estrita.
  teardown do
    logs = page.driver.browser.logs.get(:browser).map(&:message) rescue []
    offenders = logs.grep(/Content Security Policy|Uncaught|SyntaxError|TypeError|ReferenceError/)
    assert_empty offenders, "Erros de JS/CSP no navegador:\n#{offenders.join("\n")}"
  end

  def sign_in(user, password: "123456")
    visit "/login"
    fill_in "email", with: user.email
    fill_in "password", with: password
    click_button "Entrar"
    assert_current_path "/dashboard"
  end

  # Valores saem como "R$ 1.050,00" com espaço não separável.
  def assert_money(selector, amount_text)
    assert_selector selector, text: /R\$[[:space:]]*#{Regexp.escape(amount_text)}\z/
  end

  def set_date(field_id, date)
    page.execute_script("document.getElementById(#{field_id.to_json}).value = #{date.iso8601.to_json}")
  end
end
