class EventWebsiteAsset < ApplicationRecord
  belongs_to :event_website_setting
  validates :content_type, inclusion: { in: [ "image/webp" ] }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 4096 }
  validate :bounded_image_data

  def self.normalized_upload(upload)
    EventBrandingAsset.normalized_upload(upload)
  rescue EventBranding::Configuration::Invalid => error
    raise EventWebsites::Configuration::Invalid, error.message
  end

  private
    def bounded_image_data
      unless image_data.present? && image_data.bytesize <= 1.megabyte && width && height && width * height <= 12_000_000
        errors.add(:image_data, "must contain a normalized image up to 1 MB and 12 megapixels")
      end
    end
end
