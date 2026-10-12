class WallLoveNote < ApplicationRecord
  class ReviewChanged < StandardError; end

  PUBLIC_REACTIONS = [
    { public_name: "Adrian Marin", note: "That’s how you start a conference", source_url: "https://x.com/adrianthedev/status/2108056964303651174" },
    { public_name: "Marco Roth", note: "It's really great to be in India", source_url: "https://x.com/marcoroth_/status/2108067887999336677" },
    { public_name: "Irina Nazarova", note: "So so happy", source_url: "https://x.com/inazarova/status/2108059774562742562" },
    { public_name: "Animesh Ghosh", note: "ReActionView looked cool!", source_url: "https://x.com/theOnlyMaDDogx/status/2108170446503866398" }
  ].map(&:freeze).freeze

  belongs_to :user
  belongs_to :reviewed_by, class_name: "AdminUser", optional: true

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected", unpublished: "unpublished", withdrawn: "withdrawn" }, validate: true
  scope :published, -> { approved.where(publication_consent: true) }

  normalizes :public_name, :note, :source_url, with: ->(value) { value.to_s.strip.presence }
  validates :user_id, uniqueness: true
  validates :public_name, presence: true, length: { maximum: 80 }
  validates :note, presence: true, length: { maximum: 2000 }
  validates :source_url, length: { maximum: 500 }, allow_blank: true
  validates :publication_consent, acceptance: { accept: true }, unless: :withdrawn?
  validate :safe_source_url
  before_validation :return_changed_content_to_review, on: :update

  def self.safe_source_url(value)
    return if value.blank? || value.length > 500 || value.match?(/[[:cntrl:]\s]|%0[0-9a-f]|%1[0-9a-f]|%7f/i)

    uri = URI.parse(value)
    uri.to_s if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end

  def moderate!(decision:, revision:, admin:)
    raise ReviewChanged, "Administrator access required." unless admin&.admin?

    with_lock do
      raise ReviewChanged, "This note changed. Review its current content before deciding." unless revision.to_s == lock_version.to_s

      case decision
      when "approve"
        raise ReviewChanged, "Only pending notes with consent can be approved." unless pending? && publication_consent?
        self.status = :approved
      when "reject"
        raise ReviewChanged, "Only pending notes can be rejected." unless pending?
        self.status = :rejected
      when "unpublish"
        raise ReviewChanged, "Only approved notes can be unpublished." unless approved?
        self.status = :unpublished
      else
        raise ReviewChanged, "Choose a valid review decision."
      end
      self.reviewed_by = admin
      self.reviewed_at = Time.current
      save!
    end
  end

  private
    def return_changed_content_to_review
      changed_content = %w[public_name note source_url publication_consent].any? { |attribute| will_save_change_to_attribute?(attribute) }
      return unless changed_content || (will_save_change_to_status? && pending?)
      return if withdrawn?

      self.status = :pending
      self.reviewed_by = nil
      self.reviewed_at = nil
    end

    def safe_source_url
      return if source_url.blank?

      errors.add(:source_url, "must be a valid http(s) URL without login details or whitespace") unless self.class.safe_source_url(source_url)
    end
end
