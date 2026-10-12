class CreateIncomes < ActiveRecord::Migration[7.2]
  def change
    create_table :incomes do |t|
      t.string :description
      t.decimal :amount, precision: 10, scale: 2
      t.date :date
      t.string :category
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
