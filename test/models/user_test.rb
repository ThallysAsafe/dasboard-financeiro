require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "sync_recurring_entries! soma receitas e despesas e é idempotente" do
    user = users(:one)
    user.recurring_transactions.create!(
      kind: :income, description: "Salário", amount: 5000, day_of_month: 5, start_date: Date.new(2026, 1, 5)
    )
    user.recurring_transactions.create!(
      kind: :expense, description: "Aluguel", amount: 1500, day_of_month: 10, start_date: Date.new(2026, 2, 10)
    )

    # 3 receitas (jan, fev, mar) + 2 despesas (fev, mar)
    assert_equal 5, User.find(user.id).sync_recurring_entries!(today: Date.new(2026, 3, 31))
    assert_equal 0, User.find(user.id).sync_recurring_entries!(today: Date.new(2026, 3, 31))
  end

  test "sync_recurring_entries! ignora templates pausados" do
    user = users(:two)
    user.recurring_transactions.create!(
      kind: :income, description: "Freela", amount: 800, day_of_month: 1,
      start_date: Date.new(2026, 1, 1), active: false
    )

    assert_equal 0, User.find(user.id).sync_recurring_entries!(today: Date.new(2026, 6, 1))
  end

  test "o banco rejeita e-mail duplicado mesmo sem passar pela validação" do
    duplicate = User.new(email: users(:one).email, password: "123456")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "atualizar o e-mail não exige reenviar a senha, mas trocá-la valida o tamanho" do
    user = User.find(users(:one).id)

    assert user.update(email: "novo@exemplo.com")
    assert_not user.update(password: "123")
  end

  test "e-mail é normalizado (minúsculas, sem espaços) ao salvar" do
    user = User.create!(email: "  Ana@Exemplo.COM ", password: "senhaforte123")

    assert_equal "ana@exemplo.com", user.email
  end

  test "e-mail não pode repetir mudando só a caixa" do
    duplicate = User.new(email: users(:one).email.upcase, password: "123456")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:email, :taken)
  end

  test "busca por e-mail ignora a caixa" do
    assert_equal users(:one), User.find_by(email: users(:one).email.upcase)
  end

  test "e-mail com formato inválido é rejeitado" do
    %w[sem-arroba @x.com a@].each do |invalid|
      assert_not User.new(email: invalid, password: "123456").valid?, "#{invalid} deveria ser inválido"
    end
  end

  test "find_by com espaços e outra caixa encontra o usuário (base do login)" do
    assert_equal users(:one), User.find_by(email: " UM@exemplo.com ")&.authenticate("123456")
  end

  test "senha nova exige no mínimo 10 caracteres" do
    assert_not User.new(email: "a@exemplo.com", password: "123456789").valid?
    assert User.new(email: "a@exemplo.com", password: "1234567890").valid?
  end

  test "senha não pode ser igual ao e-mail" do
    user = User.new(email: "usuario@exemplo.com", password: "USUARIO@exemplo.com")

    assert_not user.valid?
    assert_includes user.errors[:password], "não pode ser igual ao e-mail"
  end

  test "conta antiga com senha curta continua podendo logar e trocar o e-mail" do
    user = User.find(users(:one).id) # fixture com senha "123456"

    assert user.authenticate("123456")
    assert user.update(email: "novo@exemplo.com")
  end

  test "authenticate_with devolve o usuário só com e-mail e senha corretos" do
    assert_equal users(:one), User.authenticate_with("um@exemplo.com", "123456")
    assert_equal users(:one), User.authenticate_with("  UM@exemplo.com ", "123456")
    assert_nil User.authenticate_with("um@exemplo.com", "errada")
    assert_nil User.authenticate_with("naoexiste@exemplo.com", "123456")
  end

  test "authenticate_with trata e-mail ou senha vazios sem levantar erro" do
    assert_nil User.authenticate_with("um@exemplo.com", "")
    assert_nil User.authenticate_with("um@exemplo.com", nil)
    assert_nil User.authenticate_with("", "123456")
    assert_nil User.authenticate_with(nil, nil)
  end

  # --- token de redefinição de senha

  test "o token de redefinição encontra o usuário" do
    token = users(:one).generate_token_for(:password_reset)

    assert_equal users(:one), User.find_by_token_for(:password_reset, token)
  end

  test "o token de redefinição expira em 30 minutos" do
    token = users(:one).generate_token_for(:password_reset)

    travel 29.minutes do
      assert_equal users(:one), User.find_by_token_for(:password_reset, token)
    end
    travel 31.minutes do
      assert_nil User.find_by_token_for(:password_reset, token)
    end
  end

  test "o token de redefinição vale uma vez só: trocar a senha o invalida" do
    user = User.find(users(:one).id)
    token = user.generate_token_for(:password_reset)

    user.update!(password: "novasenha1234")

    assert_nil User.find_by_token_for(:password_reset, token)
  end

  test "token adulterado ou de outra finalidade não redefine senha" do
    user = users(:one)

    assert_nil User.find_by_token_for(:password_reset, "lixo")
    assert_nil User.find_by_token_for(:password_reset, user.generate_token_for(:password_reset).sub(/.$/, "x"))
    assert_nil User.find_by_token_for(:password_reset, user.generate_token_for(:email_confirmation)),
               "o token de confirmação não pode servir para trocar a senha"
  end

  test "o token de um usuário não serve para outro" do
    token = users(:one).generate_token_for(:password_reset)

    assert_equal users(:one), User.find_by_token_for(:password_reset, token)
    assert_not_equal users(:two), User.find_by_token_for(:password_reset, token)
  end

  # --- confirmação de e-mail

  test "conta nova começa sem o e-mail confirmado" do
    user = User.create!(email: "novo@exemplo.com", password: "senhaforte123")

    assert_not user.email_confirmed?
    assert_nil user.email_confirmed_at
  end

  test "confirm_email! marca a data e não derruba as sessões" do
    user = User.find(users(:one).id)

    assert_no_changes -> { user.reload.token_version } do
      user.confirm_email!
    end
    assert user.email_confirmed?
  end

  test "confirm_email! é idempotente e não muda a data da primeira confirmação" do
    user = User.find(users(:one).id)
    user.confirm_email!
    primeira = user.reload.email_confirmed_at

    travel 1.hour do
      user.confirm_email!
    end

    assert_equal primeira.to_i, user.reload.email_confirmed_at.to_i
  end

  test "o token de confirmação expira em 3 dias" do
    token = users(:one).generate_token_for(:email_confirmation)

    travel 2.days do
      assert_equal users(:one), User.find_by_token_for(:email_confirmation, token)
    end
    travel 4.days do
      assert_nil User.find_by_token_for(:email_confirmation, token)
    end
  end

  test "trocar o e-mail zera a confirmação, invalida o token antigo e pede outra confirmação" do
    user = User.find(users(:one).id)
    user.confirm_email!
    token_antigo = user.generate_token_for(:email_confirmation)

    assert_enqueued_email_with UserMailer, :email_confirmation, args: [ user ] do
      user.update!(email: "trocado@exemplo.com")
    end

    assert_not user.reload.email_confirmed?
    assert_nil User.find_by_token_for(:email_confirmation, token_antigo)
  end

  test "mudar outra coisa que não o e-mail não mexe na confirmação nem manda e-mail" do
    user = User.find(users(:one).id)
    user.confirm_email!

    assert_no_enqueued_emails do
      user.update!(password: "outrasenha12345")
    end
    assert user.reload.email_confirmed?
  end

  test "criar a conta envia o e-mail de confirmação" do
    assert_enqueued_emails 1 do
      User.create!(email: "novo@exemplo.com", password: "senhaforte123")
    end
  end
end
