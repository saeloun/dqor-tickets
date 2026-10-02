class CorrectDayOneWelcomeProgramme < ActiveRecord::Migration[8.1]
  class ProgrammeItem < ActiveRecord::Base
    self.table_name = "talks"
  end

  class ProgrammeSpeaker < ActiveRecord::Base
    self.table_name = "speakers"
  end

  def up
    zone = ActiveSupport::TimeZone["Asia/Kolkata"]
    day = zone.parse("2026-10-08 00:00")
    items = ProgrammeItem.where(starts_at: day...day + 1.day)
    videos = items.where(title: "DHH welcome video").to_a
    addresses = items.where(title: "Welcome address").select do |item|
      item.speaker_name == "Amanda" || ProgrammeSpeaker.where(id: item.speaker_id, name: "Amanda").exists?
    end
    return if videos.empty? && addresses.empty?

    unless videos.one? && addresses.one?
      raise "Programme correction requires exactly one Day 1 DHH video and Amanda welcome address; inspect current schedule"
    end
    video = videos.first
    address = addresses.first
    expected_start = zone.parse("2026-10-08 10:20")
    previous_end = zone.parse("2026-10-08 10:28")
    corrected_end = zone.parse("2026-10-08 10:30")
    unless video.starts_at == previous_end && video.ends_at == corrected_end &&
        address.starts_at == expected_start && [ previous_end, corrected_end ].include?(address.ends_at)
      raise "Programme times differ from the verified 10:20–10:30 block; preserve edits and inspect before migration"
    end

    address.update_columns(ends_at: corrected_end)
    video.update_columns(published: false)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Restore the reviewed programme manually; do not republish a removed speaker automatically"
  end
end
