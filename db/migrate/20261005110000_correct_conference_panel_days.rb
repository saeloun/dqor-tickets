class CorrectConferencePanelDays < ActiveRecord::Migration[8.1]
  class ProgrammeItem < ActiveRecord::Base
    self.table_name = "talks"
  end

  ORIGINAL_TITLES = [ "Guest panel: Indian speakers", "Guest panel: international speakers" ].freeze
  CORRECTED_TITLES = ORIGINAL_TITLES.reverse.freeze
  PANEL_IDS = [ 18, 37 ].freeze
  BOOTSTRAP_PROGRAMME = [
    [ 1, 1, "Registration + चहा", "2026-10-08T04:00:00.000000Z", "2026-10-08T04:20:00.000000Z", true, nil, nil ],
    [ 2, 2, "Dhol Tasha Pathak welcome performance", "2026-10-08T04:20:00.000000Z", "2026-10-08T04:40:00.000000Z", true, nil, nil ],
    [ 3, 3, "Opening speech: How Deccan Queen began and why “Deccan Queen”", "2026-10-08T04:40:00.000000Z", "2026-10-08T04:50:00.000000Z", true, "Vipul A M", nil ],
    [ 4, 4, "Welcome address", "2026-10-08T04:50:00.000000Z", "2026-10-08T05:00:00.000000Z", true, "Amanda", nil ],
    [ 5, 5, "DHH welcome video", "2026-10-08T04:58:00.000000Z", "2026-10-08T05:00:00.000000Z", false, nil, nil ],
    [ 6, 6, "Opening keynote: When Rails Met Fibers: Migrating Sidekiq from Puma to Falcon", "2026-10-08T05:00:00.000000Z", "2026-10-08T05:45:00.000000Z", true, nil, 1 ],
    [ 7, 7, "Break", "2026-10-08T05:45:00.000000Z", "2026-10-08T05:55:00.000000Z", true, nil, nil ],
    [ 8, 8, "Loop Engineering for Rails Devs: Teaching an AI Agent to Check Its Own Homework", "2026-10-08T05:55:00.000000Z", "2026-10-08T06:25:00.000000Z", true, "Ratnadeep Deshmane", nil ],
    [ 9, 9, "Break", "2026-10-08T06:25:00.000000Z", "2026-10-08T06:35:00.000000Z", true, nil, nil ],
    [ 10, 10, "From Prompt to Rails: An Online Rails App Generator", "2026-10-08T06:35:00.000000Z", "2026-10-08T07:05:00.000000Z", true, nil, 8 ],
    [ 11, 11, "Networking and sponsor acknowledgements", "2026-10-08T07:05:00.000000Z", "2026-10-08T07:30:00.000000Z", true, nil, nil ],
    [ 12, 12, "Lunch", "2026-10-08T07:30:00.000000Z", "2026-10-08T08:30:00.000000Z", true, nil, nil ],
    [ 13, 13, "Talk by Keshav Biswa", "2026-10-08T08:30:00.000000Z", "2026-10-08T09:00:00.000000Z", true, nil, 7 ],
    [ 14, 14, "Break", "2026-10-08T09:00:00.000000Z", "2026-10-08T09:10:00.000000Z", true, nil, nil ],
    [ 15, 15, "RubyLLM 2.0: Beyond Agents", "2026-10-08T09:10:00.000000Z", "2026-10-08T09:50:00.000000Z", true, nil, 6 ],
    [ 16, 16, "चहा break", "2026-10-08T09:50:00.000000Z", "2026-10-08T10:15:00.000000Z", true, nil, nil ],
    [ 17, 17, "Closing keynote: Herb in Rails 8.2: Your ERB Views, Now HTML-Aware", "2026-10-08T10:15:00.000000Z", "2026-10-08T11:00:00.000000Z", true, nil, 2 ],
    [ 18, 18, "Guest panel", "2026-10-08T11:00:00.000000Z", "2026-10-08T11:30:00.000000Z", true, nil, nil ],
    [ 19, 19, "Day 1 wrap-up, announcements and networking", "2026-10-08T11:30:00.000000Z", "2026-10-08T12:00:00.000000Z", true, nil, nil ],
    [ 20, 20, "Networking at French Window Patisserie", "2026-10-08T13:30:00.000000Z", nil, true, nil, nil ],
    [ 21, 21, "Doors open, registration + चहा", "2026-10-09T04:00:00.000000Z", "2026-10-09T05:00:00.000000Z", true, nil, nil ],
    [ 22, 22, "Opening keynote: The Hidden 4GL", "2026-10-09T05:00:00.000000Z", "2026-10-09T05:45:00.000000Z", true, nil, 5 ],
    [ 23, 23, "Break", "2026-10-09T05:45:00.000000Z", "2026-10-09T05:50:00.000000Z", true, nil, nil ],
    [ 24, 24, "To Inertia or Not to Inertia", "2026-10-09T05:50:00.000000Z", "2026-10-09T06:20:00.000000Z", true, "Manu Janardhanan", nil ],
    [ 25, 25, "Break", "2026-10-09T06:20:00.000000Z", "2026-10-09T06:25:00.000000Z", true, nil, nil ],
    [ 26, 26, "Scaling Tool Calling in Rails: Semantic Discovery with RubyLLM and pgvector", "2026-10-09T06:25:00.000000Z", "2026-10-09T06:55:00.000000Z", true, "Rohit Joshi", nil ],
    [ 27, 27, "Break", "2026-10-09T06:55:00.000000Z", "2026-10-09T07:00:00.000000Z", true, nil, nil ],
    [ 28, 28, "I See Dead Models: what nobody tells you about running AI features in production", "2026-10-09T07:00:00.000000Z", "2026-10-09T07:30:00.000000Z", true, "Vishwajeetsingh Desurkar", nil ],
    [ 29, 29, "Lunch", "2026-10-09T07:30:00.000000Z", "2026-10-09T08:30:00.000000Z", true, nil, nil ],
    [ 30, 30, "Talk by Adrian Marin", "2026-10-09T08:30:00.000000Z", "2026-10-09T09:00:00.000000Z", true, nil, 3 ],
    [ 31, 31, "चहा break", "2026-10-09T09:35:00.000000Z", "2026-10-09T10:00:00.000000Z", true, nil, nil ],
    [ 32, 32, "Closing keynote: Agents on Rails: learnings from benchmarking AI models for the Rails Foundation", "2026-10-09T10:25:00.000000Z", "2026-10-09T10:55:00.000000Z", true, nil, 4 ],
    [ 33, 33, "Closing remarks and group photograph", "2026-10-09T10:55:00.000000Z", "2026-10-09T11:00:00.000000Z", true, nil, nil ]
  ].freeze

  def up
    transition(ORIGINAL_TITLES, CORRECTED_TITLES)
  end

  def down
    transition(CORRECTED_TITLES, ORIGINAL_TITLES)
  end

  private
    def bootstrap_programme?(items)
      projection = items.map do |item|
        [ item.id, item.position, item.title, item.starts_at&.utc&.iso8601(6),
          item.ends_at&.utc&.iso8601(6), item.published, item.speaker_name, item.speaker_id ]
      end
      projection == BOOTSTRAP_PROGRAMME && items.all? do |item|
        [ item.abstract, item.speaker_bio, item.room, item.track ].all?(&:nil?)
      end
    end

    def transition(previous, desired)
      ProgrammeItem.transaction do
        execute "SET LOCAL lock_timeout = '5s'"
        execute "SET LOCAL statement_timeout = '20s'"
        items = ProgrammeItem.order(:id).lock.to_a
        next if items.empty? || bootstrap_programme?(items)

        panels = items.select { |item| PANEL_IDS.include?(item.id) || ORIGINAL_TITLES.include?(item.title) }

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
