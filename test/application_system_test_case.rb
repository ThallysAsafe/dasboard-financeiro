require "test_helper"

# O Chrome headless, de vez em quando, não entrega à página a entrada (mouse ou
# teclado) que o Selenium despachou: nenhum evento chega ao documento, mesmo com a
# página pronta, em foco e sem nada cobrindo o botão (medido no Chrome estável, ~1
# interação em 100). O clique é conferido por uma sonda no documento e, se nada
# chegou, é despachado por JavaScript; o texto digitado é conferido no campo e, se
# não bateu, é gravado por JavaScript. Quem escreve o teste não precisa saber disso,
# e nada é refeito quando a página JÁ recebeu a entrada, então não dobra.
module ReliableClick
  ARM_PROBE = <<~JS.freeze
    window.__clicks = 0;
    if (!window.__clickProbe) {
      window.__clickProbe = true;
      document.addEventListener('click', () => { window.__clicks += 1; }, true);
    }
  JS

  def click(keys = [], **options)
    armed = arm_click_probe
    super
    return unless armed && click_lost?

    ApplicationSystemTestCase.js_fallbacks[:clique] += 1
    # Assíncrono (setTimeout) para o comando do driver voltar na hora: se o clique abrir
    # um confirm(), um clique síncrono ficaria bloqueado no diálogo, e o Capybara
    # eventual diálogo não bloqueie o comando do driver.
    begin
      driver.execute_script("const el = arguments[0]; setTimeout(() => el.click(), 0)", self)
    rescue Selenium::WebDriver::Error::StaleElementReferenceError,
           Selenium::WebDriver::Error::UnexpectedAlertOpenError
      nil # a página já mudou ou já há um diálogo: o clique chegou
    end
  end

  private

  def arm_click_probe
    driver.execute_script(ARM_PROBE)
    true
  rescue StandardError
    false
  end

  # 0 = a sonda existe e nenhum clique chegou; nil = documento novo (a página
  # navegou); erro = há um diálogo aberto. Os dois últimos significam que o clique
  # chegou.
  def click_lost?
    10.times do
      return false unless driver.evaluate_script("window.__clicks") == 0

      sleep 0.05
    end
    true
  rescue StandardError
    false
  end
end

module ReliableTyping
  TEXTUAL_INPUTS = %w[text password email number search tel url].freeze

  def set(value, **options)
    super
    return unless value.is_a?(String) || value.is_a?(Numeric)
    return unless textual_field?

    expected = value.to_s
    return if native.attribute("value") == expected

    ApplicationSystemTestCase.js_fallbacks[:digitacao] += 1
    driver.execute_script(<<~JS, self, expected)
      arguments[0].value = arguments[1];
      arguments[0].dispatchEvent(new Event('input', { bubbles: true }));
      arguments[0].dispatchEvent(new Event('change', { bubbles: true }));
    JS
  end

  private

  def textual_field?
    tag_name == "textarea" || (tag_name == "input" && TEXTUAL_INPUTS.include?(self[:type].presence || "text"))
  end
end

# Teclas especiais (Esc, Enter, Tab) enviadas com send_keys: o mesmo problema, agora no
# teclado. Se nenhum keydown chegou ao documento, o evento é despachado por JavaScript (o
# app escuta keydown no document). O texto digitado em campos já é tratado em ReliableTyping.
module ReliableKeys
  SPECIAL_KEYS = { escape: "Escape", enter: "Enter", tab: "Tab" }.freeze
  ARM_PROBE = <<~JS.freeze
    window.__keydowns = 0;
    if (!window.__keyProbe) {
      window.__keyProbe = true;
      document.addEventListener('keydown', () => { window.__keydowns += 1; }, true);
    }
  JS

  def send_keys(*args)
    specials = args.select { |key| SPECIAL_KEYS.key?(key) }
    armed = specials.any? && arm_key_probe
    super
    return unless armed && key_lost?

    ApplicationSystemTestCase.js_fallbacks[:tecla] += 1
    specials.each do |key|
      driver.execute_script("document.dispatchEvent(new KeyboardEvent('keydown', { key: arguments[0], bubbles: true }))",
                            SPECIAL_KEYS.fetch(key))
    end
  end

  private

  def arm_key_probe
    driver.execute_script(ARM_PROBE)
    true
  rescue StandardError
    false
  end

  # 0 = a sonda existe e nenhuma tecla chegou; nil = documento novo; erro = outro estado.
  def key_lost?
    10.times do
      return false unless driver.evaluate_script("window.__keydowns") == 0

      sleep 0.05
    end
    true
  rescue StandardError
    false
  end
end

Capybara::Selenium::Node.prepend(ReliableClick)
Capybara::Selenium::Node.prepend(ReliableTyping)
Capybara::Selenium::Node.prepend(ReliableKeys)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Quantas entradas o Chrome perdeu e foram refeitas por JavaScript (ver ReliableClick).
  class << self
    attr_accessor :js_fallbacks
  end
  self.js_fallbacks = Hash.new(0)

  Minitest.after_run do
    if js_fallbacks.values.sum.positive?
      puts "\nEntradas perdidas pelo Chrome e refeitas por JavaScript: #{js_fallbacks.map { |k, v| "#{k}=#{v}" }.join(', ')}"
    end
  end

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
    # Não cancelar um diálogo aberto quando o teste consulta a página.
    options.unhandled_prompt_behavior = :ignore
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
    click_button "Entrar"
    assert_dashboard_ready(user.email)
  end

  # A URL muda antes de o JavaScript da página (módulo, carregado de forma diferida)
  # registrar os handlers e terminar a primeira carga. Clicar nesse intervalo cai no
  # vazio e deixa o teste instável (visto com o Chrome estável, em máquina ocupada).
  # As páginas marcam `body[data-ready]` quando estão prontas; esperar por esse sinal
  # é determinístico, ao contrário de dormir um tempo qualquer.
  # Atenção: logo depois de um clique que navega, a página ANTIGA ainda tem data-ready.
  # Confirme o caminho (assert_current_path) antes de chamar este método.
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

  # O confirm() NATIVO não é confiável em Chrome headless: ele cancela o diálogo sozinho
  # (devolve false em ~1 ms, medido) quando a chamada não vem de um clique real do usuário,
  # o que acontece sempre que a camada de recuperação precisa refazer um clique perdido.
  # Por isso os testes trocam window.confirm por uma função que registra a pergunta e
  # devolve a resposta combinada. Continua provando o que importa: o app pergunta a coisa
  # certa e age conforme a resposta. Chame depois de visitar a página (visit zera o stub).
  def answer_confirm(accept:)
    page.execute_script(<<~JS)
      window.__confirmQuestions = [];
      window.confirm = (message) => { window.__confirmQuestions.push(message); return #{accept ? "true" : "false"}; };
    JS
  end

  def confirm_questions
    page.evaluate_script("window.__confirmQuestions") || []
  end

  # Espera o app fazer a pergunta (útil quando a resposta é "não" e nada mais muda na tela).
  def wait_for_confirm(timeout: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.05 while confirm_questions.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  # Valores saem como "R$ 1.050,00" com espaço não separável.
  def assert_money(selector, amount_text)
    assert_selector selector, text: /R\$[[:space:]]*#{Regexp.escape(amount_text)}\z/
  end

  def set_date(field_id, date)
    page.execute_script("document.getElementById(#{field_id.to_json}).value = #{date.iso8601.to_json}")
  end
end
