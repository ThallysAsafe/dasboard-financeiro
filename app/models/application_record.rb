class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # As colunas de dinheiro são decimal(10, 2): acima disso o banco recusa com
  # ActiveRecord::RangeError, que escaparia como erro 500 em vez de mensagem.
  MAX_MONEY = BigDecimal("99999999.99")
end
