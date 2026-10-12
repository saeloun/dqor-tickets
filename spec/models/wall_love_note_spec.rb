require "rails_helper"

RSpec.describe WallLoveNote, type: :model do
  let(:user) { User.create!(email: "author@example.com") }
  let(:admin) { create(:admin_user) }
  let(:attributes) { { user: user, public_name: "Public Author", note: "Thank you for the Ruby conversations.", publication_consent: true } }

  it "keeps consented submissions pending" do
    note = described_class.create!(attributes)
    expect(note).to be_pending
    expect(described_class.published).to be_empty
  end

  it "requires a deliberate public name and publication consent" do
    note = described_class.new(attributes.merge(public_name: " ", publication_consent: false))
    expect(note).not_to be_valid
    expect(note.errors).to include(:public_name, :publication_consent)
    expect(note.public_name).to be_nil
  end

  it "bounds submitted content" do
    note = described_class.new(attributes.merge(public_name: "n" * 81, note: "x" * 2001, source_url: "https://example.com/" + "x" * 500))
    expect(note).not_to be_valid
    expect(note.errors).to include(:public_name, :note, :source_url)
  end

  it "accepts public http and https links without fetching them" do
    %w[https://example.com/post?read=1#note http://example.com/profile].each do |url|
      expect(described_class.new(attributes.merge(source_url: url))).to be_valid
    end
  end

  it "rejects unsafe, malformed and credential-bearing URLs" do
    [ "javascript:alert(1)", "data:text/html,test", "//example.com", "https://user:pass@example.com", "https://example.com/with space", "https://example.com/\nsecret", "https:///post", "https://example.com/%0Asecret" ].each do |url|
      note = described_class.new(attributes.merge(source_url: url))
      expect(note).not_to be_valid, url.inspect
      expect(note.errors).to include(:source_url)
    end
  end

  it "allows only one note per user, including a database safeguard" do
    described_class.create!(attributes)
    expect(described_class.new(attributes)).not_to be_valid
    expect { described_class.transaction(requires_new: true) { described_class.new(attributes).save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "publishes exactly the revision approved by an administrator" do
    note = described_class.create!(attributes)
    note.moderate!(decision: "approve", revision: note.lock_version, admin: admin)
    expect(described_class.published).to include(note)
    expect(note.reviewed_by).to eq(admin)
  end

  it "refuses stale approval after an attendee edit" do
    note = described_class.create!(attributes)
    reviewed_revision = note.lock_version
    described_class.find(note.id).update!(note: "Changed content")
    expect { note.moderate!(decision: "approve", revision: reviewed_revision, admin: admin) }.to raise_error(described_class::ReviewChanged)
    expect(described_class.published).to be_empty
    expect(note.reload.note).to eq("Changed content")
  end

  it "removes edited approved content from publication in the same save" do
    note = described_class.create!(attributes)
    note.moderate!(decision: "approve", revision: note.lock_version, admin: admin)
    note.update!(note: "An edited note")
    expect(note).to be_pending
    expect(note.reviewed_by).to be_nil
    expect(note.reviewed_at).to be_nil
    expect(described_class.published).to be_empty
  end

  it "prevents a stale owner edit from overwriting a new review" do
    note = described_class.create!(attributes)
    stale = described_class.find(note.id)
    note.moderate!(decision: "approve", revision: note.lock_version, admin: admin)
    expect { stale.update!(note: "Unreviewed") }.to raise_error(ActiveRecord::StaleObjectError)
    expect(note.reload.note).to eq(attributes[:note])
    expect(note).to be_approved
  end

  it "supports rejection, unpublication and withdrawal without deletion" do
    note = described_class.create!(attributes)
    note.moderate!(decision: "reject", revision: note.lock_version, admin: admin)
    expect(note).to be_rejected
    note.update!(note: "Revised")
    note.moderate!(decision: "approve", revision: note.lock_version, admin: admin)
    note.moderate!(decision: "unpublish", revision: note.lock_version, admin: admin)
    expect(note).to be_unpublished
    note.update!(status: :withdrawn, publication_consent: false)
    expect(note).to be_withdrawn
    expect(described_class.published).to be_empty
  end

  it "blocks desk staff, invalid decisions and approval of withdrawn notes" do
    note = described_class.create!(attributes)
    expect { note.moderate!(decision: "approve", revision: 0, admin: create(:admin_user, role: :desk)) }.to raise_error(described_class::ReviewChanged)
    expect { note.moderate!(decision: "delete", revision: 0, admin: admin) }.to raise_error(described_class::ReviewChanged)
    note.update!(status: :withdrawn, publication_consent: false)
    expect { note.moderate!(decision: "approve", revision: note.lock_version, admin: admin) }.to raise_error(described_class::ReviewChanged)
  end

  it "removes the owner's note when their account is deleted" do
    described_class.create!(attributes)
    expect { user.destroy! }.to change(described_class, :count).by(-1)
  end

  it "filters submitted names, notes and links from record inspection and SQL binds" do
    note = described_class.new(attributes.merge(source_url: "https://example.com/private-text"))
    expect(note.inspect).not_to include(attributes[:public_name], attributes[:note], "private-text")
    messages = StringIO.new
    old_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(messages)
    begin
      note.save!
    ensure
      ActiveRecord::Base.logger = old_logger
    end
    expect(messages.string).not_to include(attributes[:public_name], attributes[:note], "private-text")
  end
end
