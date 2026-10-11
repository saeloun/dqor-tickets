require "rails_helper"

RSpec.describe "Wall of Love", type: :request do
  let(:user) { User.create!(email: "private-email@example.com") }
  let(:attributes) { { public_name: "Chosen public name", note: "Thank you, Rails friends!", source_url: "https://example.com/post", publication_consent: "1" } }

  def sign_in_attendee(attendee = user)
    get account_magic_path(token: Rails.application.message_verifier(:account_magic_link).generate(attendee.id, purpose: :account_magic_link, expires_in: 30.minutes))
  end

  def submit_note
    post wall_of_love_path, params: { wall_love_note: attributes }
  end

  def become_attendee
    create(:order, :paid, email: user.email)
    sign_in_attendee
  end

  it "shows attributed public excerpts with canonical links and sign-in CTA" do
    get wall_of_love_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Wall of Love", "Adrian Marin", "2108056964303651174", "Share your thanks", "Sign in to share a note")
    expect(response.body).not_to include("gravatar.com")
  end

  it "requires attendee sign-in to submit, edit or withdraw" do
    post wall_of_love_path, params: { wall_love_note: attributes }
    expect(response).to redirect_to(account_sign_in_path)
    patch wall_of_love_path, params: { wall_love_note: attributes }
    expect(response).to redirect_to(account_sign_in_path)
    delete wall_of_love_path
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "blocks signed-in users without an existing eligible pass" do
    sign_in_attendee
    expect { submit_note }.not_to change(WallLoveNote, :count)
    expect(response).to have_http_status(:forbidden)
    get wall_of_love_path
    expect(response.body).to include("confirmed conference pass is required")
  end

  it "uses the existing named ticket attendee policy" do
    create(:ticket, order: create(:order, :paid, email: "buyer@example.com"), attendee_email: user.email)
    sign_in_attendee
    expect { submit_note }.to change(WallLoveNote, :count).by(1)
  end

  it "requires an explicit public name without falling back to email" do
    become_attendee
    post wall_of_love_path, params: { wall_love_note: attributes.merge(public_name: "") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(WallLoveNote.count).to eq(0)
    expect(response.body).not_to include("private-email")
  end

  it "leaves publication consent unchecked including for existing notes" do
    become_attendee
    submit_note
    get wall_of_love_path
    checkbox = Nokogiri::HTML(response.body).at_css('input[type="checkbox"][name="wall_love_note[publication_consent]"]')
    expect(checkbox).to be_present
    expect(checkbox["checked"]).to be_nil
  end

  it "requires consent on the server and shows errors without publishing" do
    become_attendee
    post wall_of_love_path, params: { wall_love_note: attributes.merge(publication_consent: "0") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Publication consent must be accepted")
    expect(WallLoveNote.count).to eq(0)
  end

  it "creates a pending owner note and ignores forged publication or ownership fields" do
    become_attendee
    post wall_of_love_path, params: { wall_love_note: attributes.merge(status: "approved", user_id: User.create!(email: "other@example.com").id) }
    note = WallLoveNote.last
    expect(note.user).to eq(user)
    expect(note).to be_pending
    expect(WallLoveNote.published).to be_empty
  end

  it "treats duplicate POST as idempotent without replacing the original content" do
    become_attendee
    submit_note
    expect { post wall_of_love_path, params: { wall_love_note: attributes.merge(note: "Duplicate changed content") } }.not_to change(WallLoveNote, :count)
    expect(WallLoveNote.last.note).to eq(attributes[:note])
  end

  it "returns edited approved notes to pending and keeps rejected notes manageable" do
    become_attendee
    submit_note
    note = WallLoveNote.last
    note.moderate!(decision: "approve", revision: note.lock_version, admin: create(:admin_user))
    patch wall_of_love_path, params: { wall_love_note: attributes.merge(note: "Revised thanks", lock_version: note.lock_version) }
    expect(note.reload).to be_pending
    expect(note.note).to eq("Revised thanks")
    note.moderate!(decision: "reject", revision: note.lock_version, admin: create(:admin_user))
    get wall_of_love_path
    expect(response.body).to include("rejected", "Submit changes for review", "Withdraw my note")
  end

  it "clears the old approval when an owner resubmits unchanged content" do
    become_attendee
    submit_note
    note = WallLoveNote.last
    note.moderate!(decision: "approve", revision: note.lock_version, admin: create(:admin_user))
    patch wall_of_love_path, params: { wall_love_note: attributes.merge(lock_version: note.lock_version) }
    expect(note.reload).to be_pending
    expect(note.reviewed_by).to be_nil
    expect(note.reviewed_at).to be_nil
    expect(WallLoveNote.published).to be_empty
  end

  it "refuses owner updates missing a revision or stale after a review" do
    become_attendee
    submit_note
    note = WallLoveNote.last
    revision = note.lock_version
    patch wall_of_love_path, params: { wall_love_note: attributes }
    expect(response).to have_http_status(:bad_request)
    patch wall_of_love_path, params: { wall_love_note: attributes.merge(lock_version: "invalid") }
    expect(response).to have_http_status(:bad_request)
    note.moderate!(decision: "approve", revision: revision, admin: create(:admin_user))
    patch wall_of_love_path, params: { wall_love_note: attributes.merge(note: "Stale edit", lock_version: revision) }
    expect(response).to redirect_to(wall_of_love_path(anchor: "your-note"))
    expect(note.reload).to be_approved
    expect(note.note).to eq(attributes[:note])
  end

  it "withdraws only the signed-in owner's note even after pass eligibility changes" do
    become_attendee
    submit_note
    note = WallLoveNote.last
    note.moderate!(decision: "approve", revision: note.lock_version, admin: create(:admin_user))
    user.paid_orders.update_all(status: :canceled)
    expect { delete wall_of_love_path, params: { user_id: 999, id: 999 } }.not_to change(WallLoveNote, :count)
    expect(note.reload).to be_withdrawn
    expect(note.publication_consent).to be(false)
    expect(WallLoveNote.published).to be_empty
  end

  it "cannot edit another owner's note by supplying its ID" do
    become_attendee
    other = WallLoveNote.create!(user: User.create!(email: "other@example.com"), **attributes.merge(publication_consent: true))
    patch wall_of_love_path, params: { id: other.id, wall_love_note: attributes.merge(lock_version: 0) }
    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_pending
  end

  it "renders only approved consented notes publicly and escapes HTML" do
    note = WallLoveNote.create!(user: user, **attributes.merge(public_name: '<script>alert("name")</script>', note: '<img src=x onerror="alert(1)">', publication_consent: true))
    get wall_of_love_path
    expect(response.body).not_to include("alert(&quot;name&quot;)")
    note.moderate!(decision: "approve", revision: note.lock_version, admin: create(:admin_user))
    get wall_of_love_path
    expect(response.body).to include("&lt;script&gt;", "&lt;img")
    expect(response.body).not_to include('<script>alert("name")</script>', '<img src=x onerror=')
  end

  it "does not render unsafe stored links even when model validation was bypassed" do
    note = WallLoveNote.create!(user: user, **attributes.merge(publication_consent: true))
    note.moderate!(decision: "approve", revision: note.lock_version, admin: create(:admin_user))
    note.update_column(:source_url, "javascript:alert(1)")
    get wall_of_love_path
    expect(response.body).to include(attributes[:public_name])
    expect(response.body).not_to include("javascript:alert(1)")
  end

  it "throttles repeated submissions by attendee" do
    become_attendee
    5.times { submit_note }
    submit_note
    expect(response).to have_http_status(:too_many_requests)
    expect(WallLoveNote.count).to eq(1)
    delete wall_of_love_path
    expect(WallLoveNote.last).to be_withdrawn
    expect(response).to have_http_status(:redirect)
  end

  it "rejects missing CSRF tokens when protection is enabled" do
    become_attendee
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    submit_note
    expect(response).to have_http_status(:unprocessable_content)
    expect(WallLoveNote.count).to eq(0)
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it "filters note data from request parameter logging" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(wall_love_note: attributes)
    expect(filtered[:wall_love_note]).to eq("[FILTERED]")
  end
end
