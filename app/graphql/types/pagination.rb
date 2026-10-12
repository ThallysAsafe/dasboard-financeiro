# frozen_string_literal: true

module Types
  # Paginação por limit/offset compartilhada pelos campos de lista. O teto
  # impede que um cliente peça a tabela inteira de uma vez.
  module Pagination
    DEFAULT_PAGE_SIZE = 100
    MAX_PAGE_SIZE = 500

    private

    def paginate(scope, limit, offset)
      scope.limit(limit.clamp(1, MAX_PAGE_SIZE)).offset([ offset, 0 ].max)
    end
  end
end
