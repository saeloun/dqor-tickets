class CorrectDayTwoBreakInterval < ActiveRecord::Migration[8.1]
  class ProgrammeItem < ActiveRecord::Base
    self.table_name = "talks"
  end

  def up
    expected_start = Time.utc(2026, 10, 9, 9, 30)
    previous_end = Time.utc(2026, 10, 5, 9, 40)
    corrected_end = Time.utc(2026, 10, 9, 9, 40)
    ProgrammeItem.transaction do
      execute "SET LOCAL lock_timeout = '5s'"
      execute "SET LOCAL statement_timeout = '20s'"
      item = ProgrammeItem.lock.find_by(id: 38)
      return unless item
      unless item.title == "Break" && item.published? && item.starts_at == expected_start && [ previous_end, corrected_end ].include?(item.ends_at)
        raise "Session 38 differs from the verified published October 9 break; preserve edits and inspect before migration"
      end
      return if item.ends_at == corrected_end

      item.update_columns(ends_at: corrected_end)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Keep the corrected October 9 break interval when rolling back application code; do not restore an invalid published end time"
  end
end
