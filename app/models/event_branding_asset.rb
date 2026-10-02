class EventBrandingAsset < ApplicationRecord
  belongs_to :event_branding_setting
  validates :content_type, inclusion: { in: [ "image/webp" ] }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 4096 }
  validate :bounded_image_data

  # Bytes live in this private table, not public files or signed Active Storage URLs.
  def self.normalized_upload(upload)
    raise EventBranding::Configuration::Invalid, "Choose a raster image up to 1 MB" unless upload.respond_to?(:read) && upload.respond_to?(:size) && upload.size.between?(1, 1.megabyte)

    bytes = upload.read(1.megabyte + 1)
    raise EventBranding::Configuration::Invalid, "Choose a raster image up to 1 MB" if bytes.bytesize > 1.megabyte
    raster = bytes.start_with?("\x89PNG\r\n\x1a\n".b) || bytes.start_with?("\xff\xd8\xff".b) || (bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP")
    raise EventBranding::Configuration::Invalid, "Only PNG, JPEG and WebP images are supported" unless raster

    image = Vips::Image.new_from_buffer(bytes, "", access: :sequential, fail_on: :error)
    animated = image.get_typeof("n-pages").positive? && image.get("n-pages") > 1
    if animated || image.width > 4096 || image.height > 4096 || image.width * image.height > 12_000_000
      raise EventBranding::Configuration::Invalid, "Use a still image up to 4096 pixels per side and 12 megapixels"
    end
    normalized = image.write_to_buffer(".webp", Q: 85, strip: true)
    raise EventBranding::Configuration::Invalid, "Optimized image exceeds 1 MB; choose a smaller image" if normalized.bytesize > 1.megabyte

    { image_data: normalized, content_type: "image/webp", width: image.width, height: image.height }
  rescue Vips::Error
    raise EventBranding::Configuration::Invalid, "That file could not be decoded as a supported image"
  end

  private
    def bounded_image_data
      errors.add(:image_data, "must contain an image up to 1 MB") unless image_data.present? && image_data.bytesize <= 1.megabyte
    end
end
