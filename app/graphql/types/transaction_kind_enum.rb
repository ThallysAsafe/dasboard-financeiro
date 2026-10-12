# frozen_string_literal: true

module Types
  class TransactionKindEnum < Types::BaseEnum
    graphql_name "TransactionKind"
    description "Receita (soma no saldo) ou despesa (subtrai)"

    ::Transaction::KINDS.each_key do |kind|
      value kind.to_s.upcase, value: kind.to_s
    end
  end
end
