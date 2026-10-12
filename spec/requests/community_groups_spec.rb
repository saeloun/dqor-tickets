require "rails_helper"

RSpec.describe "Private community first events", type: :request do
  let!(:organization) { Organization.create!(name: "Synthetic Ruby", slug: "synthetic-ruby") }
  let!(:other_organization) { Organization.create!(name: "Other tenant", slug: "other-tenant") }
  let!(:user) { create(:user_for_free_pilot) }
  let!(:membership) { Membership.create!(organization: organization, user: user, role: :owner) }
  let!(:group) { organization.community_groups.create!(name: "Synthetic local rehearsal", slug: "local", timezone: "Asia/Kolkata") }
  let!(:other_group) { other_organization.community_groups.create!(name: "Other private community", slug: "other") }

  before do
    %i[organizer_platform_enabled free_event_pilot_enabled meetup_groups_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
  end

  def login
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def create_event(attributes = {}, target = group)
    post create_event_organizer_organization_group_path(organization, target), params: {
      event: { title: "First synthetic event", slug: "first", timezone: group.timezone }.merge(attributes)
    }
  end

  it "requires every independent flag for reads and writes" do
    login
    %i[organizer_platform_enabled free_event_pilot_enabled meetup_groups_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(false)
      [ organizer_organization_groups_path(organization), organizer_organization_group_path(organization, group), new_event_organizer_organization_group_path(organization, group) ].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
      expect { create_event }.not_to change(Event, :count)
      expect(response).to have_http_status(:not_found)
      expect { post organizer_organization_groups_path(organization), params: { community_group: { name: "No", slug: "no" } } }.not_to change(CommunityGroup, :count)
      expect(response).to have_http_status(:not_found)
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
  end

  it "requires verified attendee sign-in even for a global administrator" do
    get new_event_organizer_organization_group_path(organization, group)
    expect(response).to redirect_to(account_sign_in_path)
    sign_in_admin
    expect { create_event }.not_to change(Event, :count)
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "creates a private owned group without changing memberships or attendee data" do
    login
    counts = [ Membership, Event, Order, Ticket, AnnouncementCampaign ].map(&:count)
    post organizer_organization_groups_path(organization), params: { community_group: { name: "New", slug: "new", organization_id: other_organization.id, status: "published", role: "owner" } }
    expect(response).to have_http_status(:redirect)
    expect(organization.community_groups.find_by!(slug: "new")).to be_draft
    expect([ Membership, Event, Order, Ticket, AnnouncementCampaign ].map(&:count)).to eq(counts)
    expect(enqueued_jobs).to be_empty
  end

  it "allows owners and admins to create only a linked private event with no registration side effects" do
    login
    counts = [ Membership, CommunityGroup, Order, Ticket, TicketType, AnnouncementCampaign ].map(&:count)
    %i[owner admin].each do |role|
      membership.update!(role: role)
      get new_event_organizer_organization_group_path(organization, group)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
      expect(Nokogiri::HTML(response.body).at_css("input[name='event[timezone]']")["value"]).to eq("Asia/Kolkata")
      expect { create_event(slug: "first-#{role}", status: "published", organization_id: other_organization.id, community_group_id: other_group.id, user_id: user.id) }.to change(Event, :count).by(1)
      expect(response).to redirect_to(organizer_organization_group_path(organization, group))
      expect(organization.events.find_by!(slug: "first-#{role}")).to have_attributes(community_group_id: group.id, status: "draft", timezone: "Asia/Kolkata", starts_at: nil, ends_at: nil)
    end
    expect([ Membership, CommunityGroup, Order, Ticket, TicketType, AnnouncementCampaign ].map(&:count)).to eq(counts)
    expect(enqueued_jobs).to be_empty
  end

  it "retains group context and submitted fields after an invalid event and permits a retry without an orphan" do
    login
    expect { create_event(title: "Retained title", slug: "bad_slug", timezone: "Europe/London", starts_at: "2026-11-01T13:00", ends_at: "2026-11-01T14:00") }.not_to change(Event, :count)
    expect(response).to have_http_status(:unprocessable_content)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{create_event_organizer_organization_group_path(organization, group)}']")).to be_present
    expect(document.at_css("input[name='event[title]']")["value"]).to eq("Retained title")
    expect(document.at_css("input[name='event[slug]']")["value"]).to eq("bad_slug")
    expect(document.at_css("input[name='event[timezone]']")["value"]).to eq("Europe/London")
    expect(document.at_css("input[name='event[starts_at]']")["value"]).to eq("2026-11-01T13:00")
    expect(document.at_css("input[name='event[ends_at]']")["value"]).to eq("2026-11-01T14:00")
    expect(response.body).to include(group.name, "Slug is invalid")
    expect { create_event(title: "Retained title", slug: "retry", timezone: "Europe/London") }.to change(Event, :count).by(1)
    expect(organization.events.find_by!(slug: "retry")).to have_attributes(community_group_id: group.id, status: "draft")
  end

  it "scopes group reads and writes even when the user owns both organizations" do
    Membership.create!(organization: other_organization, user: user, role: :owner)
    login
    [ organizer_organization_group_path(organization, other_group), new_event_organizer_organization_group_path(organization, other_group) ].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    expect { create_event({}, other_group) }.not_to change(Event, :count)
    expect(response).to have_http_status(:not_found)
    patch organizer_organization_group_path(organization, other_group), params: { community_group: { name: "Hijacked" } }
    expect(response).to have_http_status(:not_found)
    expect(other_group.reload.name).to eq("Other private community")
  end

  it "allows editors and viewers to read only, retaining their existing event permissions" do
    login
    %i[editor viewer].each do |role|
      membership.update!(role: role)
      get organizer_organization_group_path(organization, group)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Create community event draft", "Edit community", "Add event")
      get new_event_organizer_organization_group_path(organization, group)
      expect(response).to have_http_status(:forbidden)
      expect { create_event }.not_to change(Event, :count)
      expect(response).to have_http_status(:forbidden)
      patch organizer_organization_group_path(organization, group), params: { community_group: { name: "No" } }
      expect(response).to have_http_status(:forbidden)
    end
    membership.update!(role: :editor)
    post organizer_organization_events_path(organization), params: { event: { title: "Existing editor draft", slug: "existing-editor" } }
    expect(response).to have_http_status(:redirect)
    expect(organization.events.find_by!(slug: "existing-editor").community_group_id).to be_nil
  end

  it "denies revoked and downgraded memberships on later requests" do
    login
    membership.update!(role: :viewer)
    expect { create_event }.not_to change(Event, :count)
    expect(response).to have_http_status(:forbidden)
    membership.destroy!
    expect { create_event }.not_to change(Event, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rechecks revocation inside the transaction after controller authorization" do
    login
    allow(CommunityGroups::Access).to receive(:with_manager).and_wrap_original do |original, **arguments, &block|
      membership.destroy!
      original.call(**arguments, &block)
    end
    expect { create_event }.not_to change(Event, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "rechecks a role downgrade inside the transaction after controller authorization" do
    login
    allow(CommunityGroups::Access).to receive(:with_manager).and_wrap_original do |original, **arguments, &block|
      membership.update!(role: :editor)
      original.call(**arguments, &block)
    end
    expect { create_event }.not_to change(Event, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "attaches only owned events idempotently without publication or moving linked events" do
    login
    event = organization.events.create!(title: "Owned", slug: "owned")
    post add_event_organizer_organization_group_path(organization, group), params: { event_id: event.id }
    expect(event.reload).to have_attributes(community_group_id: group.id, status: "draft")
    updated = event.updated_at
    post add_event_organizer_organization_group_path(organization, group), params: { event_id: event.id }
    expect(event.reload.updated_at).to eq(updated)
    another = organization.community_groups.create!(name: "Another", slug: "another")
    post add_event_organizer_organization_group_path(organization, another), params: { event_id: event.id }
    expect(event.reload.community_group_id).to eq(group.id)
    foreign = other_organization.events.create!(title: "Foreign", slug: "foreign")
    post add_event_organizer_organization_group_path(organization, group), params: { event_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.community_group_id).to be_nil
    expect(enqueued_jobs).to be_empty
  end

  it "has no group publication actions or new public group routes" do
    login
    get organizer_organization_group_path(organization, group)
    expect(response.body).not_to include("Publish community", "View public community", "Make community private")
    %w[publish unpublish].each do |action|
      post "/organizer/organizations/#{organization.id}/groups/#{group.id}/#{action}"
      expect(response).to have_http_status(:not_found)
    end
    get "/communities"
    expect(response).to have_http_status(:not_found)
    get "/api/public/v1/communities"
    expect(response).to have_http_status(:not_found)
    expect(community_path).to eq("/community")
  end
end
