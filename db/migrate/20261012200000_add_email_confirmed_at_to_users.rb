class AddEmailConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  # Nulo = e-mail ainda não confirmado. Contas que já existiam também ficam sem
  # confirmação: ninguém verificou aquele endereço, e o dashboard só mostra um aviso.
  def change
    add_column :users, :email_confirmed_at, :datetime
  end
end
