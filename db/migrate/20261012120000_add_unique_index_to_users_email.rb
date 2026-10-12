class AddUniqueIndexToUsersEmail < ActiveRecord::Migration[7.2]
  # A validação de unicidade sozinha não resiste a duas requisições
  # simultâneas; o índice único é a garantia real.
  def change
    remove_index :users, :email
    add_index :users, :email, unique: true
  end
end
