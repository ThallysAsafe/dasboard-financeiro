class AddWalletToIncomesAndExpenses < ActiveRecord::Migration[7.2]
  def change
    add_reference :incomes, :wallet, null: true, foreign_key: true
    add_reference :expenses, :wallet, null: true, foreign_key: true
  end
end
