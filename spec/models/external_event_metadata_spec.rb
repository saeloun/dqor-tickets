require "rails_helper"

RSpec.describe "External event metadata", type: :model do
  let!(:organization) { Organization.create!(name: "Ruby", slug: "ruby") }
  let(:event) { organization.events.new(title: "Meetup", slug: "meetup", starts_at: Time.utc(2026, 10, 24, 4, 30), ends_at: Time.utc(2026, 10, 24, 7, 30), timezone: "Asia/Kolkata") }

  it "canonicalizes Luma aliases and tracking while retaining other source query semantics" do
    event.source_url = "http://lu.ma/48awjqkg/?utm_source=poster#section"
    expect(event.source_url).to eq("https://luma.com/48awjqkg")
    event.source_url = "https://example.com/events?event=1&utm_source=poster"
    expect(event.source_url).to eq("https://example.com/events?event=1&utm_source=poster")
    event.source_url = "https://luma.com/48awjqkg?event=1&utm_source=poster"
    expect(event.source_url).to eq("https://luma.com/48awjqkg?event=1")
  end

  it "rejects unsafe schemes credentials whitespace control characters and incomplete hosts for each link" do
    %i[source_url external_registration_url cfp_url].each do |attribute|
      [ "javascript:alert(1)", "data:text/html,test", "//luma.com/test", "https://user:password@luma.com/test", "https://luma.com/a b", "https://luma.com/a\nb", "https:///event", "https://" ].each do |url|
        event.assign_attributes(source_url: nil, external_registration_url: nil, cfp_url: nil)
        event.public_send("#{attribute}=", url)
        expect(event).not_to be_valid, "#{attribute} accepted #{url.inspect}"
        expect(event.errors).to include(attribute)
      end
    end
  end

  it "permits ordinary metadata-free drafts and limits oversized imported text" do
    event.assign_attributes(source_url: "", external_registration_url: "", cfp_url: "")
    expect(event).to be_valid
    expect(event.source_url).to be_nil
    event.import_notes = "x" * 20_001
    expect(event).not_to be_valid
  end

  it "enforces source uniqueness in the database even when validations are skipped" do
    event.update!(source_url: "https://luma.com/48awjqkg")
    duplicate = organization.events.create!(title: "Other", slug: "other")
    expect do
      Event.transaction(requires_new: true) { duplicate.update_columns(source_url: event.source_url) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "reuses the scoped record after a concurrent unique-index race" do
    event.source_url = "https://luma.com/48awjqkg"
    winner = organization.events.create!(event.attributes.except("id", "created_at", "updated_at").merge(slug: "winner"))
    importer = Event::DraftImport.new(event)
    allow(importer).to receive(:existing_event).and_return(nil, winner)
    allow(event).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)
    result = importer.call
    expect(result.status).to eq(:existing)
    expect(result.event).to eq(winner)
    expect(organization.events.count).to eq(1)
  end

  it "reuses the record if a concurrent insert is observed by uniqueness validation" do
    event.source_url = "https://luma.com/48awjqkg"
    winner = organization.events.create!(event.attributes.except("id", "created_at", "updated_at").merge(slug: "winner"))
    importer = Event::DraftImport.new(event)
    allow(importer).to receive(:existing_event).and_return(nil, winner)
    expect(importer.call.status).to eq(:existing)
  end
end
