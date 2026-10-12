require "rails_helper"

RSpec.describe "Wall of Love moderation", type: :request do
  let!(:note) { WallLoveNote.create!(user: User.create!(email: "author@example.com"), public_name: "Chosen name", note: "A lovely conference", publication_consent: true) }

  it "requires existing administrator access, excluding desk staff" do
    get wall_love_review_path(note)
    expect(response).to redirect_to(new_session_path)
    sign_in_admin(create(:admin_user, role: :desk, password: "password123"))
    get wall_love_review_path(note)
    expect(response).to have_http_status(:forbidden)
    patch wall_love_review_path(note), params: { decision: "approve", lock_version: 0 }
    expect(response).to have_http_status(:forbidden)
    expect(note.reload).to be_pending
  end

  it "shows exact content and the review revision then approves it" do
    sign_in_admin
    get wall_love_review_path(note)
    expect(response.body).to include("Chosen name", "A lovely conference", 'name="lock_version"', "Approve publication")
    patch wall_love_review_path(note), params: { decision: "approve", lock_version: note.lock_version }
    expect(note.reload).to be_approved
  end

  it "rejects stale decisions without publishing changed content" do
    sign_in_admin
    revision = note.lock_version
    note.update!(note: "Edited after preview")
    patch wall_love_review_path(note), params: { decision: "approve", lock_version: revision }
    expect(note.reload).to be_pending
    expect(WallLoveNote.published).to be_empty
    expect(flash[:alert]).to include("could not be saved")
  end

  it "does not expose unsafe stored links during moderation" do
    sign_in_admin
    note.update_column(:source_url, "data:text/html,<script>alert(1)</script>")
    get wall_love_review_path(note)
    expect(response.body).to include(note.public_name)
    expect(response.body).not_to include("data:text/html", "<script>alert(1)</script>")
  end

  it "supports rejection and unpublication without deleting notes" do
    sign_in_admin
    patch wall_love_review_path(note), params: { decision: "reject", lock_version: note.lock_version }
    expect(note.reload).to be_rejected
    note.update!(note: "Resubmitted")
    patch wall_love_review_path(note), params: { decision: "approve", lock_version: note.lock_version }
    patch wall_love_review_path(note), params: { decision: "unpublish", lock_version: note.reload.lock_version }
    expect(note.reload).to be_unpublished
    expect(WallLoveNote.count).to eq(1)
  end

  it "provides a read-only Avo queue with a publication review action" do
    sign_in_admin
    get "/avo/resources/wall_love_notes"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Chosen name", "Review publication")
    post "/avo/resources/wall_love_notes/#{note.id}/actions", params: { action_id: "Avo::Actions::ReviewWallLoveNote", resource_name: "wall_love_notes", fields: { avo_resource_ids: note.id.to_s } }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(Rails.application.routes.url_helpers.wall_love_review_path(note))
    patch "/avo/resources/wall_love_notes/#{note.id}", params: { wall_love_note: { status: "approved" } }
    expect(response).to have_http_status(:forbidden)
    expect(note.reload).to be_pending
  end
end
