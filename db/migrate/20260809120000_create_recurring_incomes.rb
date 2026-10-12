class CreateRecurringIncomes < ActiveRecord::Migration[7.2]
  def change
    create_table :recurring_incomes do |t|
      t.string :description, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :day_of_month, null: false
      t.date :start_date, null: false
      t.date :end_date
      t.string :category
      t.boolean :active, null: false, default: true
      t.date :last_generated_on
      t.references :user, null: false, foreign_key: true
      t.references :wallet, null: true, foreign_key: true

      t.timestamps
    end

    add_index :recurring_incomes, [ :user_id, :active ]
  end
end
