# Cada usuário passa a ter exatamente UMA carteira, e todo lançamento (e template)
# pertence a ela.
#
# Para quem tinha várias carteiras, elas são fundidas na mais antiga: os
# lançamentos vão para ela e os saldos iniciais são SOMADOS, então o saldo total
# do usuário não muda. Quem não tinha carteira ganha uma. Lançamentos sem carteira
# (ou presos à carteira de outro usuário) vão para a carteira do dono.
#
# O saldo de cada usuário é conferido antes e depois; qualquer divergência aborta
# a migração e nada é gravado.
class OneWalletPerUser < ActiveRecord::Migration[7.2]
  def up
    before = balances

    execute <<~SQL
      INSERT INTO wallets (name, initial_balance, user_id, created_at, updated_at)
      SELECT 'Carteira', 0, u.id, NOW(), NOW()
      FROM users u
      WHERE NOT EXISTS (SELECT 1 FROM wallets w WHERE w.user_id = u.id)
    SQL

    # Funde as carteiras extras na mais antiga de cada usuário.
    execute <<~SQL
      CREATE TEMPORARY TABLE wallet_merge AS
      SELECT w.id AS old_id,
             (SELECT MIN(k.id) FROM wallets k WHERE k.user_id = w.user_id) AS keeper_id
      FROM wallets w
    SQL
    %w[transactions recurring_transactions].each do |table|
      execute <<~SQL
        UPDATE #{table} t SET wallet_id = m.keeper_id
        FROM wallet_merge m WHERE t.wallet_id = m.old_id AND m.old_id <> m.keeper_id
      SQL
    end
    execute <<~SQL
      UPDATE wallets k SET initial_balance = k.initial_balance + extra.total
      FROM (
        SELECT m.keeper_id, SUM(w.initial_balance) AS total
        FROM wallet_merge m JOIN wallets w ON w.id = m.old_id
        WHERE m.old_id <> m.keeper_id GROUP BY m.keeper_id
      ) extra
      WHERE k.id = extra.keeper_id
    SQL
    execute "DELETE FROM wallets WHERE id IN (SELECT old_id FROM wallet_merge WHERE old_id <> keeper_id)"
    execute "DROP TABLE wallet_merge"

    # Sem carteira, ou presos à carteira de outro usuário: vão para a do dono.
    %w[transactions recurring_transactions].each do |table|
      execute <<~SQL
        UPDATE #{table} t SET wallet_id = w.id
        FROM wallets w
        WHERE w.user_id = t.user_id
          AND (t.wallet_id IS NULL OR t.wallet_id NOT IN (SELECT id FROM wallets WHERE user_id = t.user_id))
      SQL
    end

    change_column_null :transactions, :wallet_id, false
    change_column_null :recurring_transactions, :wallet_id, false
    remove_index :wallets, :user_id
    add_index :wallets, :user_id, unique: true

    verify!(before)
  end

  # Só restaura as restrições. A fusão das carteiras não é desfeita: os lançamentos
  # e saldos continuam na carteira que sobrou.
  def down
    remove_index :wallets, :user_id
    add_index :wallets, :user_id
    change_column_null :recurring_transactions, :wallet_id, true
    change_column_null :transactions, :wallet_id, true
  end

  private

  # Saldo de cada usuário pela regra antiga: soma dos saldos iniciais de todas as
  # carteiras + receitas − despesas.
  def balances
    select_rows(<<~SQL).to_h { |id, balance| [ id.to_i, balance.to_d ] }
      SELECT u.id,
             COALESCE((SELECT SUM(initial_balance) FROM wallets WHERE user_id = u.id), 0)
           + COALESCE((SELECT SUM(amount) FROM transactions WHERE user_id = u.id AND kind = 0), 0)
           - COALESCE((SELECT SUM(amount) FROM transactions WHERE user_id = u.id AND kind = 1), 0)
      FROM users u
    SQL
  end

  def verify!(before)
    after = balances
    before.each do |user_id, balance|
      raise "Migração abortada: saldo do usuário #{user_id} mudou (#{balance} -> #{after[user_id]})" unless after[user_id] == balance
    end

    bad = select_value("SELECT COUNT(*) FROM users u WHERE (SELECT COUNT(*) FROM wallets WHERE user_id = u.id) <> 1").to_i
    raise "Migração abortada: #{bad} usuário(s) sem exatamente 1 carteira" unless bad.zero?

    mismatched = select_value(<<~SQL).to_i
      SELECT (SELECT COUNT(*) FROM transactions t JOIN wallets w ON w.id = t.wallet_id WHERE w.user_id <> t.user_id)
           + (SELECT COUNT(*) FROM recurring_transactions t JOIN wallets w ON w.id = t.wallet_id WHERE w.user_id <> t.user_id)
    SQL
    raise "Migração abortada: #{mismatched} registro(s) em carteira de outro usuário" unless mismatched.zero?
  end
end
