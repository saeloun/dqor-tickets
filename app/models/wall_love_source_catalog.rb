class WallLoveSourceCatalog
  FEATURED_IDS = %w[S016 S012 S002 S007 S015 S021 S022 S005 S006 S046 S064 S065 S066 S067].freeze
  SOURCES = JSON.parse(Rails.root.join("config/wall_love_sources.json").read).fetch("sources").map(&:freeze).freeze
  VOICE_LABELS = { "attendee_or_speaker" => "Community voice", "host_and_sponsor" => "Host perspective", "organiser_published_ownership_not_proven" => "From the organisers", "pre_event_context" => "Before the gathering", "conference_association_unverified" => "Related technical context" }.freeze

  def self.featured
    FEATURED_IDS.filter_map { |id| SOURCES.find { |source| source.fetch("id") == id } }
  end

  def self.main_wall
    SOURCES.select { |source| source.fetch("include_in_main_wall") }.sort_by { |source| source.fetch("display_order") }
  end

  def self.archive
    SOURCES.select { |source| source.fetch("section") == "before_the_event" }
  end

  def self.related
    SOURCES.select { |source| source.fetch("section") == "related_technical_context" }
  end

  def self.voice_label(source)
    source.fetch("section") == "rails_girls" ? "Related activity · Rails Girls" : VOICE_LABELS.fetch(source.fetch("voice_role"))
  end

  def self.filter_groups(source)
    groups = [ source.fetch("section") ]
    groups << "on_stage" if source.values_at("card_title", "caption").join(" ").match?(/keynote|session|panel|talk|on stage|welcome address/i)
    groups.join(" ")
  end
end
