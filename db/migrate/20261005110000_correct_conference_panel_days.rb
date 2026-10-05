class CorrectConferencePanelDays < ActiveRecord::Migration[8.1]
  class ProgrammeItem < ActiveRecord::Base
    self.table_name = "talks"
  end

  ORIGINAL_TITLES = [ "Guest panel: Indian speakers", "Guest panel: international speakers" ].freeze
  CORRECTED_TITLES = ORIGINAL_TITLES.reverse.freeze
  PANEL_IDS = [ 18, 37 ].freeze

  def up
    transition(ORIGINAL_TITLES, CORRECTED_TITLES)
  end

  def down
    transition(CORRECTED_TITLES, ORIGINAL_TITLES)
  end

  private
    def transition(previous, desired)
      ProgrammeItem.transaction do
        execute "SET LOCAL lock_timeout = '5s'"
        execute "SET LOCAL statement_timeout = '20s'"
        panels = ProgrammeItem.where(id: PANEL_IDS).or(ProgrammeItem.where(title: ORIGINAL_TITLES)).order(:id).lock.to_a
        next if panels.empty? && !ProgrammeItem.exists?

        expected_times = [
          [ Time.utc(2026, 10, 8, 9, 50), Time.utc(2026, 10, 8, 10, 20) ],
          [ Time.utc(2026, 10, 9, 9, 40), Time.utc(2026, 10, 9, 10, 20) ]
        ]
        unless panels.map(&:id) == PANEL_IDS && panels.each_with_index.all? { |panel, index|
            panel.published? && [ panel.starts_at, panel.ends_at ] == expected_times[index]
          } && [ previous, desired ].include?(panels.map(&:title))
          raise "Panel programme differs from the verified IDs, titles, publication or time slots; inspect before migration"
        end
        next if panels.map(&:title) == desired

        panels.zip(desired).each do |panel, title|
          ProgrammeItem.where(id: panel.id).update_all(title: title)
        end
      end
    end
end
