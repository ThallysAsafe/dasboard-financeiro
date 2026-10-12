class NormalizeUsersEmail < ActiveRecord::Migration[7.2]
  # Passa os e-mails existentes para minúsculas, igual ao que o model faz agora.
  # Se dois usuários só diferirem na caixa, o índice único estoura de propósito:
  # decidir qual conta sobrevive não é algo que uma migration deva adivinhar.
  def up
    execute "UPDATE users SET email = LOWER(TRIM(email))"
  end

  def down; end
end
