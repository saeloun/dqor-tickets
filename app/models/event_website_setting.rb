class EventWebsiteSetting < ApplicationRecord
  class StaleDraft < StandardError; end
  class AccessDenied < StandardError; end

  belongs_to :event
  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :published_by, class_name: "User", optional: true
  has_many :assets, class_name: "EventWebsiteAsset", dependent: :restrict_with_exception
  validates :event_id, uniqueness: true
  validates :draft, presence: true
  validate :valid_snapshots

  def self.for_event(event)
    find_by(event_id: event.id) || new(event:, draft: EventWebsites::Configuration.defaults.to_h)
  end

  def save_draft!(values:, uploads:, removals:, expected_version:, actor:)
    unless uploads.is_a?(Hash) && (uploads.keys - EventWebsites::Configuration::ASSETS).empty? && removals.is_a?(Array) && (removals - EventWebsites::Configuration::ASSETS).empty?
      raise EventWebsites::Configuration::Invalid, "Choose a supported image slot"
    end
    raise AccessDenied, "Event manager access is required" unless actor.is_a?(User) && actor.persisted? && Membership.find_by(user_id: actor.id, organization_id: Event.find(event_id).organization_id)&.manage_events?
    normalized = uploads.transform_values { |upload| EventWebsiteAsset.normalized_upload(upload) }
    mutate(expected_version:, actor:) do |setting|
      setting.save! unless setting.persisted?
      asset_ids = setting.draft.fetch("assets").dup
      removals.each { |slot| asset_ids.delete(slot) }
      normalized.each { |slot, attributes| asset_ids[slot] = setting.assets.create!(attributes).id }
      setting.draft = EventWebsites::Configuration.new(values.merge("assets" => asset_ids)).to_h
      setting.updated_by = actor
      setting.save!
    end
  end

  def publish!(expected_version:, actor:)
    mutate(expected_version:, actor:) do |setting|
      raise EventWebsites::Configuration::Invalid, "Save a draft before publishing" unless setting.persisted?
      setting.previous_published = setting.published.deep_dup
      setting.published = setting.draft.deep_dup
      setting.published_by = actor
      setting.published_at = Time.current
      setting.save!
    end
  end

  def restore!(expected_version:, actor:)
    mutate(expected_version:, actor:) do |setting|
      raise EventWebsites::Configuration::Invalid, "No prior publication is available" unless setting.previous_published
      setting.published, setting.previous_published = setting.previous_published.deep_dup, setting.published.deep_dup
      setting.published_by = actor
      setting.published_at = Time.current
      setting.save!
    end
  end

  private
    def mutate(expected_version:, actor:)
      raise AccessDenied, "Event membership is required" unless actor.is_a?(User) && actor.persisted?
      self.class.transaction do
        scoped_event = Event.find(event_id)
        membership = Membership.lock.find_by(user_id: actor.id, organization_id: scoped_event.organization_id)
        raise AccessDenied, "Event manager access is required" unless membership&.manage_events?
        scoped_event.lock!
        raise AccessDenied, "Event membership changed" unless scoped_event.organization_id == membership.organization_id
        setting = self.class.lock.find_by(event_id: scoped_event.id) || self
        unless expected_version.is_a?(Integer) && expected_version == setting.lock_version
          raise StaleDraft, "This website changed in another session. Reload and review before trying again."
        end
        yield setting
        setting
      end
    end

    def valid_snapshots
      configurations = [ draft, published, previous_published ].compact.map { |snapshot| EventWebsites::Configuration.new(snapshot) }
      referenced_ids = configurations.flat_map(&:asset_ids).uniq
      errors.add(:base, "Website images must belong to this event") unless (referenced_ids - assets.where(id: referenced_ids).pluck(:id)).empty?
    rescue EventWebsites::Configuration::Invalid => error
      errors.add(:base, error.message)
    end
end
