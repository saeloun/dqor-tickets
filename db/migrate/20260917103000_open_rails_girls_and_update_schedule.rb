class OpenRailsGirlsAndUpdateSchedule < ActiveRecord::Migration[8.1]
  SCHEDULE = [
    [ 8, "09:30", "09:50", "Registration + चहा", nil ],
    [ 8, "09:50", "10:10", "Dhol Tasha Pathak welcome performance", nil ],
    [ 8, "10:10", "10:20", "Opening speech: How Deccan Queen began and why “Deccan Queen”", "Vipul A M" ],
    [ 8, "10:20", "10:28", "Welcome address", "Amanda" ],
    [ 8, "10:28", "10:30", "DHH welcome video", nil ],
    [ 8, "10:30", "11:15", "Opening keynote: When Rails Met Fibers: Migrating Sidekiq from Puma to Falcon", "Samuel Williams" ],
    [ 8, "11:15", "11:25", "Break", nil ],
    [ 8, "11:25", "11:55", "Loop Engineering for Rails Devs: Teaching an AI Agent to Check Its Own Homework", "Ratnadeep Deshmane" ],
    [ 8, "11:55", "12:05", "Break", nil ],
    [ 8, "12:05", "12:35", "From Prompt to Rails: An Online Rails App Generator", "Paweł Strzałkowski" ],
    [ 8, "12:35", "13:00", "Networking and sponsor acknowledgements", nil ],
    [ 8, "13:00", "14:00", "Lunch", nil ],
    [ 8, "14:00", "14:30", "Talk by Keshav Biswa", "Keshav Biswa" ],
    [ 8, "14:30", "14:40", "Break", nil ],
    [ 8, "14:40", "15:20", "RubyLLM 2.0: Beyond Agents", "Carmine Paolino" ],
    [ 8, "15:20", "15:45", "चहा break", nil ],
    [ 8, "15:45", "16:30", "Closing keynote: Herb in Rails 8.2: Your ERB Views, Now HTML-Aware", "Marco Roth" ],
    [ 8, "16:30", "17:00", "Guest panel", nil ],
    [ 8, "17:00", "17:30", "Day 1 wrap-up, announcements and networking", nil ],
    [ 8, "19:00", nil, "Networking at French Window Patisserie", nil ],
    [ 9, "09:30", "10:30", "Doors open, registration + चहा", nil ],
    [ 9, "10:30", "11:15", "Opening keynote: The Hidden 4GL", "Sam Ruby" ],
    [ 9, "11:15", "11:20", "Break", nil ],
    [ 9, "11:20", "11:50", "To Inertia or Not to Inertia", "Manu Janardhanan" ],
    [ 9, "11:50", "11:55", "Break", nil ],
    [ 9, "11:55", "12:25", "Scaling Tool Calling in Rails: Semantic Discovery with RubyLLM and pgvector", "Rohit Joshi" ],
    [ 9, "12:25", "12:30", "Break", nil ],
    [ 9, "12:30", "13:00", "I See Dead Models: what nobody tells you about running AI features in production", "Vishwajeetsingh Desurkar" ],
    [ 9, "13:00", "14:00", "Lunch", nil ],
    [ 9, "14:00", "14:30", "Talk by Adrian Marin", "Adrian Marin" ],
    [ 9, "15:05", "15:30", "चहा break", nil ],
    [ 9, "15:55", "16:25", "Closing keynote: Agents on Rails: learnings from benchmarking AI models for the Rails Foundation", "Irina Nazarova" ],
    [ 9, "16:25", "16:30", "Closing remarks and group photograph", nil ]
  ].freeze

  def up
    open_rails_girls
    publish_schedule
  end

  def down
  end

  private
    def open_rails_girls
      TicketType.where(slug: "explore-pune-day").update_all(position: 6)
      TicketType.where(slug: "complimentary-pass").update_all(position: 7)

      TicketType.find_or_initialize_by(slug: "rails-girls-pune").update!(
        name: "Rails Girls Pune Pass",
        description: "One-day beginner workshop on October 10. Build a Rails app with help from coaches. Bring a laptop.",
        price_paise: 35_000,
        capacity: nil,
        active: true,
        hidden: false,
        requires_conference_pass: false,
        position: 5
      )
    end

    def publish_schedule
      zone = ActiveSupport::TimeZone["Asia/Kolkata"]

      SCHEDULE.each_with_index do |(day, starts_at, ends_at, title, speaker_name), index|
        talk = Talk.find_or_initialize_by(position: index + 1)
        speaker = Speaker.find_by(name: speaker_name) if speaker_name
        talk.update!(
          title: title,
          speaker: speaker,
          speaker_name: speaker ? nil : speaker_name,
          starts_at: zone.parse("2026-10-#{day} #{starts_at}"),
          ends_at: ends_at && zone.parse("2026-10-#{day} #{ends_at}"),
          published: true
        )
      end

      Talk.where.not(position: 1..SCHEDULE.length).update_all(published: false)
    end
end
