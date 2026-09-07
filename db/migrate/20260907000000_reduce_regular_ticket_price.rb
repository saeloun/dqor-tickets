class ReduceRegularTicketPrice < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE ticket_types
      SET price_paise = 350000, updated_at = CURRENT_TIMESTAMP
      WHERE slug = 'conference-pass-regular'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE ticket_types
      SET price_paise = 550000, updated_at = CURRENT_TIMESTAMP
      WHERE slug = 'conference-pass-regular' AND price_paise = 350000
    SQL
  end
end
