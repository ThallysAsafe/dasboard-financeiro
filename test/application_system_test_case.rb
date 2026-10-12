require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # CHROME_BIN / CHROMEDRIVER_PATH existem no container de desenvolvimento
  # (Dockerfile.dev); no CI o Chrome vem do runner e o Selenium acha sozinho.
  Selenium::WebDriver::Chrome::Service.driver_path = ENV["CHROMEDRIVER_PATH"] if ENV["CHROMEDRIVER_PATH"]

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
    options.add_argument("--no-sandbox")            # roda como root no container
    options.add_argument("--disable-dev-shm-usage") # /dev/shm pequeno no Docker
    # Sem isto o Chrome headless pode frear timers e o processamento de entrada de uma
    # janela que considera "em segundo plano", e cliques são descartados de vez em
    # quando. São os mesmos padrões que o Puppeteer usa para automação estável.
    options.add_argument("--disable-background-timer-throttling")
    options.add_argument("--disable-backgrounding-occluded-windows")
    options.add_argument("--disable-renderer-backgrounding")
    # Os testes não dependem da internet: as fontes do Google chegam em momentos
    # diferentes, trocam a fonte no meio do teste e deslocam o layout, o que faz
    # cliques caírem no lugar errado. Bloqueadas, a página usa a fonte local e fica
    # sempre igual.
    options.add_argument("--host-resolver-rules=MAP fonts.googleapis.com 127.0.0.1,MAP fonts.gstatic.com 127.0.0.1")
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
  end

  setup do
    Capybara.default_max_wait_time = 10 # o runner do CI é mais lento que uma máquina local
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
    click_with_retry(-> { find_button("Entrar") }) { |wait| page.has_current_path?("/dashboard", wait: wait) }
    assert_dashboard_ready(user.email)
  end

  # O Chrome headless descarta, muito raramente, um clique mesmo com a página pronta
  # (visto só no Chrome estável, em uma de cada ~90 interações). Reclicar é seguro
  # quando o clique é idempotente (entrar, abrir o formulário); NÃO use em ações que
  # alternam estado (pausar, excluir). O bloco diz se o efeito esperado apareceu.
  def click_with_retry(finder, attempts: 3, wait: 3, &effect)
    attempts.times do
      finder.call.click
      return if effect.call(wait)
    end
  end

  # A URL muda antes de o JavaScript da página (módulo, carregado de forma diferida)
  # registrar os handlers e terminar a primeira carga. Clicar nesse intervalo cai no
  # vazio e deixa o teste instável (visto com o Chrome estável, em máquina ocupada).
  # As páginas marcam `body[data-ready]` quando estão prontas; esperar por esse sinal
  # é determinístico, ao contrário de dormir um tempo qualquer.
  def assert_page_ready
    assert_selector "body[data-ready='true']"
  end

  def assert_dashboard_ready(email)
    assert_current_path "/dashboard"
    assert_page_ready
    assert_selector "#userEmailDisplay", text: email
  end

  # Toda página do app está pronta para uso só depois do sinal acima.
  def visit(*)
    super
    assert_page_ready
  end

  # Valores saem como "R$ 1.050,00" com espaço não separável.
  def assert_money(selector, amount_text)
    assert_selector selector, text: /R\$[[:space:]]*#{Regexp.escape(amount_text)}\z/
  end

  def set_date(field_id, date)
    page.execute_script("document.getElementById(#{field_id.to_json}).value = #{date.iso8601.to_json}")
  end
end
