class SeedAnnouncedSpeakers < ActiveRecord::Migration[8.1]
  # Publicly-announced speakers only (already listed on the marketing site / home page).
  # Titles are the public one-liners from the home page. No non-announced names here.
  ANNOUNCED = [
    [ "Samuel Williams", "Creator of Async Ruby" ],
    [ "Marco Roth", "Stimulus & Turbo Contributor" ],
    [ "Adrian Marin", "Author of Avo and Marksmith" ],
    [ "Irina Nazarova", "CEO of Evil Martians" ],
    [ "Sam Ruby", "Co-author of AWDR" ],
    [ "Carmine Paolino", "Creator of RubyLLM & Chat with Work" ],
    [ "Keshav Biswa", "Creator of Confuscript" ],
    [ "Paweł Strzałkowski", "CTO at Visuality & Author of Hifumi" ]
  ].freeze

  def up
    ANNOUNCED.each_with_index do |(name, title), index|
      speaker = Speaker.find_or_initialize_by(name: name)
      speaker.title = title if speaker.title.blank?
      speaker.status = :announced
      speaker.published = true
      speaker.position = index + 1 if speaker.position.to_i.zero?
      speaker.save!
    end
  end

  def down
    # Intentionally left as a no-op: announced speakers are public content and
    # should not be removed on rollback.
  end
end
