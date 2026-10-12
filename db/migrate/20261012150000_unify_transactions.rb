# Junta receitas e despesas (e seus templates recorrentes) em tabelas únicas com
# uma coluna `kind`. Os dados são copiados e conferidos (contagem, soma e vínculos
# com a recorrência); qualquer divergência aborta a migração e nada é gravado.
class UnifyTransactions < ActiveRecord::Migration[7.2]
  INCOME = 0
  EXPENSE = 1

  def up
    create_table :recurring_transactions do |t|
      t.integer :kind, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.integer :day_of_month, null: false
      t.date :start_date, null: false
      t.date :end_date
      t.string :category
      t.boolean :active, null: false, default: true
      t.date :last_generated_on
      t.references :user, null: false, foreign_key: true
      t.references :wallet, foreign_key: true
      t.bigint :legacy_id # id do template antigo, só durante a cópia
      t.timestamps
    end
    add_index :recurring_transactions, [ :user_id, :active ]

    create_table :transactions do |t|
      t.integer :kind, null: false
      t.string :description, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.date :date, null: false
      t.string :category
      t.references :user, null: false, foreign_key: true
      t.references :wallet, foreign_key: true
      t.references :recurring_transaction, foreign_key: true
      t.timestamps
    end
    # NULLs são distintos em índice único no Postgres, então lançamentos manuais
    # (FK nula) nunca colidem; vale como invariante contra duplicata gerada.
    add_index :transactions, [ :recurring_transaction_id, :date ], unique: true,
              name: "index_transactions_on_recurring_transaction_and_date"
    add_index :transactions, [ :user_id, :kind, :date ]

    { INCOME => "recurring_incomes", EXPENSE => "recurring_expenses" }.each do |kind, table|
      execute <<~SQL
        INSERT INTO recurring_transactions
          (kind, description, amount, day_of_month, start_date, end_date, category, active,
           last_generated_on, user_id, wallet_id, legacy_id, created_at, updated_at)
        SELECT #{kind}, description, amount, day_of_month, start_date, end_date, category, active,
               last_generated_on, user_id, wallet_id, id, created_at, updated_at
        FROM #{table} ORDER BY id
      SQL
    end

    { INCOME => %w[incomes recurring_income_id], EXPENSE => %w[expenses recurring_expense_id] }.each do |kind, (table, link)|
      execute <<~SQL
        INSERT INTO transactions
          (kind, description, amount, date, category, user_id, wallet_id,
           recurring_transaction_id, created_at, updated_at)
        SELECT #{kind}, t.description, t.amount, t.date, t.category, t.user_id, t.wallet_id,
               rt.id, t.created_at, t.updated_at
        FROM #{table} t
        LEFT JOIN recurring_transactions rt ON rt.kind = #{kind} AND rt.legacy_id = t.#{link}
        ORDER BY t.id
      SQL
    end

    verify_copy!

    remove_column :recurring_transactions, :legacy_id
    drop_table :incomes
    drop_table :expenses
    drop_table :recurring_incomes
    drop_table :recurring_expenses
  end

  def down
    create_table :recurring_incomes do |t|
      recurring_columns(t)
    end
    create_table :recurring_expenses do |t|
      recurring_columns(t)
    end
    create_table :incomes do |t|
      entry_columns(t)
    end
    create_table :expenses do |t|
      entry_columns(t)
    end
    add_reference :incomes, :recurring_income, foreign_key: true
    add_reference :expenses, :recurring_expense, foreign_key: true
    add_index :incomes, [ :recurring_income_id, :date ], unique: true,
              name: "index_incomes_on_recurring_income_and_date"
    add_index :expenses, [ :recurring_expense_id, :date ], unique: true,
              name: "index_expenses_on_recurring_expense_and_date"

    # Os templates mantêm o id que tinham em recurring_transactions (é o que liga
    # os lançamentos a eles); as sequências são ajustadas depois.
    { INCOME => [ "recurring_incomes", "incomes", "recurring_income_id" ],
      EXPENSE => [ "recurring_expenses", "expenses", "recurring_expense_id" ] }.each do |kind, (rec_table, table, link)|
      execute <<~SQL
        INSERT INTO #{rec_table}
          (id, description, amount, day_of_month, start_date, end_date, category, active,
           last_generated_on, user_id, wallet_id, created_at, updated_at)
        SELECT id, description, amount, day_of_month, start_date, end_date, category, active,
               last_generated_on, user_id, wallet_id, created_at, updated_at
        FROM recurring_transactions WHERE kind = #{kind} ORDER BY id
      SQL
      execute "SELECT setval(pg_get_serial_sequence('#{rec_table}', 'id'), COALESCE(MAX(id), 1)) FROM #{rec_table}"

      execute <<~SQL
        INSERT INTO #{table}
          (description, amount, date, category, user_id, wallet_id, #{link}, created_at, updated_at)
        SELECT description, amount, date, category, user_id, wallet_id, recurring_transaction_id,
               created_at, updated_at
        FROM transactions WHERE kind = #{kind} ORDER BY id
      SQL
    end

    drop_table :transactions
    drop_table :recurring_transactions
  end

  private

  # Confere a cópia antes de apagar as tabelas antigas.
  def verify_copy!
    [ [ INCOME, "incomes", "recurring_incomes", "recurring_income_id" ],
      [ EXPENSE, "expenses", "recurring_expenses", "recurring_expense_id" ] ].each do |kind, table, rec_table, link|
      expect_same!("#{table}: contagem", count("SELECT COUNT(*) FROM #{table}"),
                   count("SELECT COUNT(*) FROM transactions WHERE kind = #{kind}"))
      expect_same!("#{table}: soma", count("SELECT COALESCE(SUM(amount), 0) FROM #{table}"),
                   count("SELECT COALESCE(SUM(amount), 0) FROM transactions WHERE kind = #{kind}"))
      expect_same!("#{table}: vínculos com a recorrência",
                   count("SELECT COUNT(*) FROM #{table} WHERE #{link} IS NOT NULL"),
                   count("SELECT COUNT(*) FROM transactions WHERE kind = #{kind} AND recurring_transaction_id IS NOT NULL"))
      expect_same!("#{rec_table}: contagem", count("SELECT COUNT(*) FROM #{rec_table}"),
                   count("SELECT COUNT(*) FROM recurring_transactions WHERE kind = #{kind}"))
    end
  end

  def count(sql)
    select_value(sql).to_d
  end

  def expect_same!(label, before, after)
    raise "Migração abortada: #{label} diverge (antes #{before}, depois #{after})" unless before == after
  end

  def recurring_columns(t)
    t.string :description, null: false
    t.decimal :amount, precision: 10, scale: 2, null: false
    t.integer :day_of_month, null: false
    t.date :start_date, null: false
    t.date :end_date
    t.string :category
    t.boolean :active, null: false, default: true
    t.date :last_generated_on
    t.references :user, null: false, foreign_key: true
    t.references :wallet, foreign_key: true
    t.timestamps
    t.index [ :user_id, :active ]
  end

  def entry_columns(t)
    t.string :description
    t.decimal :amount, precision: 10, scale: 2
    t.date :date
    t.string :category
    t.references :user, null: false, foreign_key: true
    t.references :wallet, foreign_key: true
    t.timestamps
  end
end
