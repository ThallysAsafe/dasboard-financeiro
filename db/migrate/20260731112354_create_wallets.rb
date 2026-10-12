class CreateWallets < ActiveRecord::Migration[7.2]
  def change
    create_table :wallets do |t|
      t.string :name, null: false
      t.decimal :initial_balance, precision: 10, scale: 2, default: 0.0, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
