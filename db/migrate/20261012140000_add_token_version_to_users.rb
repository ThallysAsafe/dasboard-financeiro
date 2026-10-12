class AddTokenVersionToUsers < ActiveRecord::Migration[7.2]
  # Todo JWT carrega a versão vigente do usuário; incrementar a coluna
  # invalida de uma vez todos os tokens já emitidos (logout, troca de senha).
  def change
    add_column :users, :token_version, :integer, null: false, default: 0
  end
end
