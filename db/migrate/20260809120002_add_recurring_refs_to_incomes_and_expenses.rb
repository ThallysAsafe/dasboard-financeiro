class AddRecurringRefsToIncomesAndExpenses < ActiveRecord::Migration[7.2]
  def change
    add_reference :incomes, :recurring_income, null: true, foreign_key: true
    add_reference :expenses, :recurring_expense, null: true, foreign_key: true

    # NULLs são distintos em índice único no Postgres, então lançamentos manuais
    # (FK nula) nunca colidem entre si. Vale como invariante contra duplicata gerada.
    add_index :incomes, [ :recurring_income_id, :date ], unique: true,
              name: "index_incomes_on_recurring_income_and_date"
    add_index :expenses, [ :recurring_expense_id, :date ], unique: true,
              name: "index_expenses_on_recurring_expense_and_date"
  end
end
