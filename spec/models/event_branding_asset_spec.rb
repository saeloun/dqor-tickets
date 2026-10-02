require "rails_helper"

RSpec.describe EventBrandingAsset do
  def upload(bytes)
    file = StringIO.new(bytes)
    file
  end

  it "rejects oversize input before reading it" do
    file = instance_double(ActionDispatch::Http::UploadedFile, size: 1.megabyte + 1)
    allow(file).to receive(:read)
    expect { described_class.normalized_upload(file) }.to raise_error(EventBranding::Configuration::Invalid, /1 MB/)
    expect(file).not_to have_received(:read)
  end

  it "rejects a recognizable signature with an invalid image payload" do
    expect { described_class.normalized_upload(upload("\x89PNG\r\n\x1a\n".b + "invalid")) }.to raise_error(EventBranding::Configuration::Invalid, /decoded/)
  end

  it "rejects oversized image dimensions before re-encoding" do
    bytes = Vips::Image.black(4097, 1).write_to_buffer(".png")
    expect { described_class.normalized_upload(upload(bytes)) }.to raise_error(EventBranding::Configuration::Invalid, /4096/)
  end

  it "strips metadata by re-encoding supported image bytes" do
    image = Vips::Image.black(12, 12)
    image.set_type(GObject::GSTR_TYPE, "comment", "private test metadata")
    bytes = image.write_to_buffer(".png")
    result = described_class.normalized_upload(upload(bytes))
    expect(result).to include(content_type: "image/webp", width: 12, height: 12)
    expect(result.fetch(:image_data)).not_to include("private test metadata")
  end
end
