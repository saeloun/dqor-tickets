class EventBrandingSetting < ApplicationRecord
  class StaleDraft < StandardError; end
  PUBLIC_RENDERING_ENABLED = false

  has_many :assets, class_name: "EventBrandingAsset", dependent: :destroy
  belongs_to :updated_by, class_name: "AdminUser", optional: true
  belongs_to :published_by, class_name: "AdminUser", optional: true
  validates :event_key, inclusion: { in: [ "dqor" ] }
  validate :valid_snapshots

  def self.current
    find_by(event_key: "dqor") || create_or_find_by!(event_key: "dqor") { |setting| setting.draft = EventBranding::Configuration.defaults.to_h }
  end

  def save_draft!(values:, uploads:, removals:, expected_version:, actor:)
    require_organizer!(actor)
    normalized = uploads.transform_values { |upload| EventBrandingAsset.normalized_upload(upload) }
    with_lock do
      verify_version!(expected_version)
      asset_ids = draft.fetch("assets").dup
      removals.each { |slot| asset_ids.delete(slot) }
      normalized.each { |slot, attributes| asset_ids[slot] = assets.create!(attributes).id }
      self.draft = EventBranding::Configuration.new(values.merge("assets" => asset_ids)).to_h
      self.updated_by = actor
      save!
      prune_assets!
    end
  end

  def publish!(expected_version:, actor:)
    require_organizer!(actor)
    with_lock do
      verify_version!(expected_version)
      self.previous_published = published.deep_dup
      self.published = draft.deep_dup
      self.published_by = actor
      self.published_at = Time.current
      save!
      prune_assets!
    end
  end

  def rollback!(expected_version:, actor:)
    require_organizer!(actor)
    with_lock do
      verify_version!(expected_version)
      raise EventBranding::Configuration::Invalid, "No previous published configuration is available" unless previous_published
      self.published, self.previous_published = previous_published.deep_dup, published.deep_dup
      self.published_by = actor
      self.published_at = Time.current
      save!
    end
  end

  # Deliberately unused by public controllers. Activation requires a separate
  # integration review covering storefront, emails, PDFs, favicon and rollback.
  def configuration_for_public_rendering
    EventBranding::Configuration.new(published) if PUBLIC_RENDERING_ENABLED && published
  end

  private
    def require_organizer!(actor)
      raise EventBranding::Configuration::Invalid, "Organizer access is required" unless actor&.admin?
    end

    def verify_version!(expected_version)
      raise StaleDraft, "This configuration changed in another session. Reload and review before trying again." unless expected_version == lock_version
    end

    def valid_snapshots
      [ draft, published, previous_published ].compact.each do |snapshot|
        config = EventBranding::Configuration.new(snapshot)
        errors.add(:base, "Brand images must belong to this event configuration") unless (config.asset_ids - assets.pluck(:id)).empty?
      rescue EventBranding::Configuration::Invalid => error
        errors.add(:base, error.message)
      end
    end

    def prune_assets!
      used = [ draft, published, previous_published ].compact.flat_map { |snapshot| snapshot.fetch("assets").values }.uniq
      assets.where.not(id: used).destroy_all
    end
end
