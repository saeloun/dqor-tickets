class PublishConferenceSchedule < ActiveRecord::Migration[8.1]
  ZONE = "Asia/Kolkata"

  SESSIONS = [
    [ 8, 9, 0, 9, 20, "Registration + चहा" ],
    [ 8, 9, 20, 9, 40, "Dhol Tasha Pathak welcome performance" ],
    [ 8, 9, 40, 9, 50, "How Deccan Queen began and why “Deccan Queen”", [ "Vipul A M", "Vipul" ] ],
    [ 8, 9, 50, 9, 58, "Welcome address", [ "Amanda" ] ],
    [ 8, 9, 58, 10, 0, "DHH welcome video" ],
    [ 8, 10, 0, 10, 45, "Opening keynote", [ "Samuel Williams" ] ],
    [ 8, 10, 45, 10, 50, "Break" ],
    [ 8, 10, 50, 11, 20, "Talk by Ratnadeep Deshmane", [ "Ratnadeep Deshmane" ] ],
    [ 8, 11, 20, 11, 25, "Break" ],
    [ 8, 11, 25, 11, 55, "From Prompt to Rails: An Online Rails App Generator", [ "Paweł Strzałkowski" ] ],
    [ 8, 11, 55, 12, 0, "Break" ],
    [ 8, 12, 0, 12, 30, "Rails.event in Action: Subscribers and Dashboards", [ "Keshav Biswa", "Keshav" ] ],
    [ 8, 12, 30, 13, 0, "Networking and sponsor acknowledgements + buffer" ],
    [ 8, 13, 0, 14, 0, "Lunch" ],
    [ 8, 14, 0, 14, 30, "Talk by Carmine Paolino", [ "Carmine Paolino" ] ],
    [ 8, 15, 5, 15, 30, "चहा break" ],
    [ 8, 16, 30, 17, 15, "Opening keynote", [ "Marco Roth" ] ],
    [ 8, 17, 15, 17, 30, "Day 1 wrap-up and announcements" ],
    [ 8, 19, 0, nil, nil, "Networking at French Window Patisserie" ],
    [ 9, 9, 30, 10, 0, "Doors open + चहा" ],
    [ 9, 10, 30, 10, 50, "Closing keynote", [ "Sam Ruby" ] ],
    [ 9, 10, 50, 11, 20, "Break" ],
    [ 9, 11, 20, 11, 25, "To Inertia or Not to Inertia", [ "Manu Janardhanan", "Manu J" ] ],
    [ 9, 11, 25, 11, 55, "Break" ],
    [ 9, 11, 55, 12, 0, "Stop Registering Your Tools: Scaling LLM Tool Calling in Rails with ruby-llm and pgvector", [ "Rohit Joshi" ] ],
    [ 9, 12, 0, 12, 30, "Break" ],
    [ 9, 12, 30, 13, 0, "What If… Ruby Led the AI Revolution?", [ "Vishwajeetsingh Desurkar", "Vishwajeet Desurkar" ] ],
    [ 9, 13, 0, 14, 0, "Lunch" ],
    [ 9, 14, 35, 15, 5, "Talk by Adrian Marin", [ "Adrian Marin" ] ],
    [ 9, 15, 5, 15, 30, "चहा break" ],
    [ 9, 15, 55, 16, 25, "Guest panel" ],
    [ 9, 16, 25, 16, 30, "Break" ],
    [ 9, 16, 30, 17, 15, "Closing keynote", [ "Irina Nazarova", "Irina" ] ],
    [ 9, 17, 15, 17, 30, "Closing remarks and group photograph" ]
  ].freeze

  def up
    Talk.reset_column_information
    Speaker.reset_column_information
    zone = Time.find_zone!(ZONE)

    SESSIONS.each_with_index do |(day, start_hour, start_minute, end_hour, end_minute, title, speaker_names), position|
      starts_at = zone.local(2026, 10, day, start_hour, start_minute)
      ends_at = zone.local(2026, 10, day, end_hour, end_minute) if end_hour
      speaker = Speaker.find_by(name: speaker_names) if speaker_names

      talk = if speaker
        speaker.talks.first_or_initialize
      elsif speaker_names
        Talk.where(speaker_name: speaker_names).first_or_initialize
      else
        Talk.find_or_initialize_by(title: title, starts_at: starts_at)
      end

      talk.title = title if talk.title.blank?
      talk.speaker = speaker
      talk.speaker_name = speaker ? nil : speaker_names&.first
      talk.starts_at = starts_at
      talk.ends_at = ends_at
      talk.position = position + 1
      talk.published = true
      talk.save!
    end
  end

  def down
    # Public programme data may collect bookmarks, questions, and feedback.
  end
end
