# Template de um lançamento que se repete todo mês (salário, aluguel…). Ele não é
# saldo: materializa lançamentos reais (Transaction) pelo `generate_entries!`.
class RecurringTransaction < ApplicationRecord
  # Teto de retroação. Protege contra um template com start_date muito antigo
  # tentando materializar centenas de lançamentos de uma vez.
  MAX_BACKFILL_MONTHS = 120

  include WalletBound

  # Nullify e não destroy: os lançamentos já gerados aconteceram de verdade e
  # continuam valendo para o saldo histórico mesmo sem o template.
  has_many :transactions, dependent: :nullify

  enum :kind, Transaction::KINDS, validate: true

  validates :description, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :day_of_month, presence: true,
            numericality: { only_integer: true,
                            greater_than_or_equal_to: 1,
                            less_than_or_equal_to: 31 }
  validates :start_date, presence: true
  validate :end_date_after_start_date
  # Só ao criar ou ao mudar a data de início: um template antigo não pode ficar
  # inválido (e impossível de pausar) só porque a janela andou com o tempo.
  validate :start_date_within_backfill_window, if: -> { new_record? || will_save_change_to_start_date? }

  scope :active, -> { where(active: true) }

  # Trava `day` no último dia válido do mês da âncora: dia 31 vira 28/02 em 2026,
  # 29/02 em 2028 e 30/04 em qualquer ano.
  def self.occurrence_date(month_anchor, day)
    Date.new(month_anchor.year, month_anchor.month, [ day, month_anchor.end_of_month.day ].min)
  end

  # Primeiro mês que o backfill alcança. Antes disso os lançamentos nunca seriam
  # gerados, então a data de início é recusada em vez de cortada em silêncio.
  def self.earliest_start_date(today: Date.current)
    (today - (MAX_BACKFILL_MONTHS - 1).months).beginning_of_month
  end

  # Pura, sem tocar no banco. Todas as ocorrências ainda devidas, da mais antiga
  # para a mais nova. Nunca devolve data futura: dinheiro que ainda não entrou
  # não pode entrar no total.
  def occurrence_dates(today: Date.current)
    limit = [ today, end_date ].compact.min
    return [] if limit.blank? || start_date.blank? || day_of_month.blank?

    anchor = (last_generated_on ? last_generated_on.next_month : start_date).beginning_of_month
    # -1 porque a janela inclui os dois extremos: de `floor` até `today` são
    # exatamente MAX_BACKFILL_MONTHS meses. O corte tem que ser aqui, e não no
    # tamanho da lista: o loop caminha do mais antigo para o mais novo, então
    # parar por tamanho descartaria justamente os meses recentes.
    floor = self.class.earliest_start_date(today: today)
    anchor = floor if anchor < floor

    dates = []
    while anchor <= limit.beginning_of_month
      dates << self.class.occurrence_date(anchor, day_of_month)
      anchor = anchor.next_month
    end

    dates.select { |date| date >= start_date && date <= limit }
  end

  # Primeira ocorrência estritamente depois de hoje, ou nil quando a recorrência
  # já acabou ou está pausada.
  def next_occurrence(today: Date.current)
    return nil unless active?

    anchor = [ today.beginning_of_month, start_date.beginning_of_month ].max
    3.times do
      date = self.class.occurrence_date(anchor, day_of_month)
      return nil if end_date && date > end_date
      return date if date > today && date >= start_date

      anchor = anchor.next_month
    end
    nil
  end

  # Cria os lançamentos que faltam e devolve quantos foram criados.
  def generate_entries!(today: Date.current)
    return 0 unless active?
    # Caminho rápido do dia a dia: nada devido, nenhum lock e nenhuma escrita.
    return 0 if occurrence_dates(today: today).empty?

    created = 0
    with_lock do
      # Recalculado sob o lock: uma segunda aba pode ter gerado no meio tempo.
      dates = occurrence_dates(today: today)

      if dates.any?
        existing = transactions.where(date: dates).pluck(:date)
        (dates - existing).each do |date|
          transactions.create!(
            kind: kind,
            user_id: user_id,
            wallet_id: wallet_id,
            description: description,
            amount: amount,
            category: category,
            date: date
          )
          created += 1
        end

        # Marca d'água em nível de mês. Sem ela, um lançamento gerado e depois
        # apagado pelo usuário voltaria no próximo carregamento da página.
        update_column(:last_generated_on, dates.last)
      end
    end

    created
  end

  private

  def start_date_within_backfill_window
    return if start_date.blank?

    earliest = self.class.earliest_start_date
    return if start_date >= earliest

    errors.add(:start_date, "não pode ser anterior a #{I18n.l(earliest)} (o limite de retroação é de #{MAX_BACKFILL_MONTHS} meses)")
  end

  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?

    errors.add(:end_date, "deve ser igual ou posterior à data de início") if end_date < start_date
  end
end
