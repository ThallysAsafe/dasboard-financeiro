require "application_system_test_case"
require "minitest/mock"

# Garante as camadas ReliableClick e ReliableTyping (application_system_test_case.rb):
# quando o Chrome perde um clique ou o texto digitado, é refeito por JavaScript, uma
# única vez.
class ClickReliabilityTest < ApplicationSystemTestCase
  setup do
    Transaction.where(user: users(:one)).delete_all
    sign_in users(:one)
  end

  def novo_botao
    first("[data-action='open-create'][data-kind='income']")
  end

  def cliques_recebidos_pela_pagina
    page.evaluate_script("window.__clicks")
  end

  test "um clique entregue normalmente chega uma única vez" do
    novo_botao.click

    assert_selector "#entryModal.open"
    assert_equal 1, cliques_recebidos_pela_pagina
  end

  test "um clique que o navegador perdeu é refeito por JavaScript" do
    node = novo_botao
    antes = ApplicationSystemTestCase.js_fallbacks[:clique]

    node.native.stub(:click, nil) { node.click } # o "navegador" perde o clique

    assert_selector "#entryModal.open"
    assert_equal 1, cliques_recebidos_pela_pagina, "o clique refeito não pode chegar duas vezes"
    assert_operator ApplicationSystemTestCase.js_fallbacks[:clique], :>, antes
  end

  test "o clique perdido num botão que pede confirmação é refeito e a pergunta é feita" do
    users(:one).transactions.create!(kind: :expense, description: "Mercado", amount: 40, date: Date.current)
    visit "/dashboard"
    answer_confirm(accept: true)
    node = find("#expensesList [data-action='delete']")

    node.native.stub(:click, nil) { node.click }

    assert_text "Nenhuma despesa cadastrada ainda."
    assert_equal [ 'Excluir "Mercado"?' ], confirm_questions, "perguntou uma única vez"
    assert_equal 0, users(:one).transactions.expense.count
  end

  test "recusar a confirmação depois de um clique perdido mantém o lançamento" do
    users(:one).transactions.create!(kind: :expense, description: "Mercado", amount: 40, date: Date.current)
    visit "/dashboard"
    answer_confirm(accept: false)
    node = find("#expensesList [data-action='delete']")

    node.native.stub(:click, nil) { node.click }

    wait_for_confirm
    assert_equal [ 'Excluir "Mercado"?' ], confirm_questions
    assert_selector "#expensesList .entry-row", count: 1
    assert_equal 1, users(:one).transactions.expense.count
  end

  test "clique que navega a página não é refeito nem quebra" do
    click_button "Sair" # volta ao login (o setup deixou a sessão aberta)
    assert_current_path "/login"
    assert_page_ready
    click_link "Cadastre-se"

    assert_current_path "/signup"
  end

  # --- digitação

  test "o texto digitado fica no campo exatamente uma vez" do
    click_button "Sair"
    assert_current_path "/login" # só o caminho prova que trocou de página: a antiga também tem data-ready
    assert_page_ready
    fill_in "email", with: "alguem@exemplo.com"

    # Exatamente o que foi digitado, sem duplicar (o Chrome pode perder a digitação de
    # verdade e a camada refaz; o resultado tem de ser o mesmo nos dois casos).
    assert_equal "alguem@exemplo.com", find_field("email").value
  end

  test "texto que o navegador perdeu é gravado por JavaScript e vira o valor do campo" do
    click_button "Sair"
    assert_current_path "/login" # só o caminho prova que trocou de página: a antiga também tem data-ready
    assert_page_ready
    campo = find_field("password")
    antes = ApplicationSystemTestCase.js_fallbacks[:digitacao]

    campo.native.stub(:send_keys, nil) { campo.set("segredo-longo-123") } # o "navegador" perde as teclas

    assert_equal "segredo-longo-123", find_field("password").value
    assert_operator ApplicationSystemTestCase.js_fallbacks[:digitacao], :>, antes
  end

  test "login completo mesmo quando o navegador perde a digitação" do
    click_button "Sair"
    assert_current_path "/login" # só o caminho prova que trocou de página: a antiga também tem data-ready
    assert_page_ready
    fill_in "email", with: users(:one).email
    campo = find_field("password")

    campo.native.stub(:send_keys, nil) { campo.set("123456") }
    click_button "Entrar"

    assert_dashboard_ready(users(:one).email)
  end
end
