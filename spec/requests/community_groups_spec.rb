require "rails_helper"

RSpec.describe "Tenant-owned communities", type: :request do
  let!(:organization) { Organization.create!(name: "Synthetic Ruby", slug: "synthetic-ruby") }
  let!(:other_organization) { Organization.create!(name: "Other tenant", slug: "other-tenant") }
  let!(:user) { create(:user_for_free_pilot) }
  let!(:membership) { Membership.create!(organization: organization, user: user, role: :owner) }
  let!(:group) { organization.community_groups.create!(name: "Pune Ruby rehearsal", slug: "pune-ruby", description: "Synthetic local rehearsal", city: "Pune", country_code: "IN", timezone: "Asia/Kolkata") }
  let!(:other_group) { other_organization.community_groups.create!(name: "Other private community", slug: "private") }

  before do
    %i[organizer_platform_enabled free_event_pilot_enabled meetup_groups_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
  end

  def login
    token = Rails.application.message_verifier(:account_magic_link).generate(user.id, purpose: :account_magic_link, expires_in: 30.minutes)
    get account_magic_path(token: token)
  end

  def public_path
    community_group_public_path(organization.slug, group.slug)
  end

  def api_path
    public_community_path(organization.slug, group.slug)
  end

  def add_event(event, target = group)
    post add_event_organizer_organization_group_path(organization, target), params: { event_id: event.id }
  end

  it "requires every independent feature flag before public or private group access" do
    login
    %i[organizer_platform_enabled free_event_pilot_enabled meetup_groups_enabled].each do |flag|
      allow(Rails.configuration.x).to receive(flag).and_return(false)
      [ communities_path, public_communities_path, public_path, api_path, organizer_organization_groups_path(organization) ].each do |path|
        get path
        expect(response).to have_http_status(:not_found)
      end
      expect { post organizer_organization_groups_path(organization), params: { community_group: { name: "No", slug: "no" } } }.not_to change(CommunityGroup, :count)
      expect(response).to have_http_status(:not_found)
      allow(Rails.configuration.x).to receive(flag).and_return(true)
    end
  end

  it "requires verified attendee sign-in and ignores a global administrator session" do
    get organizer_organization_groups_path(organization)
    expect(response).to redirect_to(account_sign_in_path)
    sign_in_admin
    get organizer_organization_groups_path(organization)
    expect(response).to redirect_to(account_sign_in_path)
  end

  it "creates only a private owned draft and rejects tenant, status and membership mass assignment" do
    login
    counts = [ Membership, Event, Order, Ticket, AnnouncementCampaign ].map(&:count)
    post organizer_organization_groups_path(organization), params: { community_group: { name: "New community", slug: "new", organization_id: other_organization.id, status: "published", role: "owner" } }
    expect(response).to have_http_status(:redirect)
    expect(organization.community_groups.find_by!(slug: "new")).to be_draft
    expect([ Membership, Event, Order, Ticket, AnnouncementCampaign ].map(&:count)).to eq(counts)
    expect(enqueued_jobs).to be_empty
  end

  it "allows an existing organization admin without permitting tenant or publication reassignment" do
    membership.update!(role: :admin)
    login
    patch organizer_organization_group_path(organization, group), params: { community_group: { name: "Admin update", organization_id: other_organization.id, status: "published" } }
    expect(response).to have_http_status(:redirect)
    expect(group.reload).to have_attributes(name: "Admin update", organization_id: organization.id, status: "draft")
    post publish_organizer_organization_group_path(organization, group)
    expect(group.reload).to be_published
    expect(Membership.count).to eq(1)
  end

  it "lists published communities only and exposes no public mutation route" do
    group.update!(status: :published)
    get public_communities_path
    expect(response.parsed_body["groups"].pluck("id")).to eq([ "community-#{group.id}" ])
    get communities_path
    expect(response.body).to include(group.name)
    expect(response.body).not_to include(other_group.name)
    expect { post public_communities_path, params: { community_group: { name: "Forged" } } }.not_to change(CommunityGroup, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "scopes reads and writes even when the user belongs to both tenants" do
    Membership.create!(organization: other_organization, user: user, role: :owner)
    login
    get organizer_organization_group_path(organization, other_group)
    expect(response).to have_http_status(:not_found)
    patch organizer_organization_group_path(organization, other_group), params: { community_group: { name: "Hijacked" } }
    expect(response).to have_http_status(:not_found)
    post publish_organizer_organization_group_path(organization, other_group)
    expect(response).to have_http_status(:not_found)
    foreign_event = other_organization.events.create!(title: "Foreign", slug: "foreign")
    add_event(foreign_event)
    expect(response).to have_http_status(:not_found)
    expect(foreign_event.reload.community_group_id).to be_nil
    expect(other_group.reload).to have_attributes(name: "Other private community", status: "draft")
  end

  it "allows existing editors and viewers to read but not manage communities" do
    login
    %i[editor viewer].each do |role|
      membership.update!(role: role)
      get organizer_organization_group_path(organization, group)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Publish community", "Edit community")
      patch organizer_organization_group_path(organization, group), params: { community_group: { name: "No" } }
      expect(response).to have_http_status(:forbidden)
      post publish_organizer_organization_group_path(organization, group)
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "rechecks revocation and role changes on the next request and locked service mutation" do
    login
    get organizer_organization_groups_path(organization)
    expect(response).to have_http_status(:ok)
    membership.update!(role: :viewer)
    expect { CommunityGroups::Access.with_manager(user: user, organization_id: organization.id) { group.update!(name: "No") } }.to raise_error(ActiveRecord::RecordNotFound)
    membership.destroy!
    post publish_organizer_organization_group_path(organization, group)
    expect(response).to have_http_status(:not_found)
    expect(group.reload).to be_draft
  end

  it "keeps an invalid publication private with visible errors and a retry control" do
    login
    group.update!(description: nil)
    post publish_organizer_organization_group_path(organization, group)
    expect(response).to have_http_status(:unprocessable_content)
    expect(group.reload).to be_draft
    expect(response.body).to include("Draft · private", "Description can&#39;t be blank", "Publish community")
    expect(response.body).not_to include("Published · public", "View public community")
  end

  it "attaches owned events idempotently without publishing or moving another community's event" do
    login
    event = organization.events.create!(title: "Owned draft", slug: "owned")
    add_event(event)
    expect(event.reload).to have_attributes(community_group_id: group.id, status: "draft")
    first_update = event.updated_at
    add_event(event)
    expect(event.reload.updated_at).to eq(first_update)
    another_group = organization.community_groups.create!(name: "Another", slug: "another")
    add_event(event, another_group)
    expect(response).to have_http_status(:redirect)
    expect(event.reload.community_group_id).to eq(group.id)
    expect(enqueued_jobs).to be_empty
  end

  it "publishes only complete group facts and owned published events without attendee or native scopes" do
    login
    get public_path
    expect(response).to have_http_status(:not_found)
    get api_path
    expect(response).to have_http_status(:not_found)
    group.update!(description: "<script>alert('private')</script>")
    event = organization.events.create!(title: "<script>Gathering</script>", slug: "public", status: :published, starts_at: 1.day.from_now, ends_at: 2.days.from_now, timezone: "Asia/Kolkata", community_group: group)
    organization.events.create!(title: "Unpublished secret", slug: "secret", community_group: group)
    post publish_organizer_organization_group_path(organization, group)
    expect(group.reload).to be_published
    get public_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("&lt;script&gt;", "Asia/Kolkata")
    expect(response.body).not_to include("<script>alert", "Unpublished secret")
    get api_path
    data = response.parsed_body
    expect(data["group"]).to include("id" => "community-#{group.id}", "ownership" => "tenant_owned_community")
    expect(data["upcoming_events"].first).to include("id" => "hosted-event-#{event.id}", "timezone" => "Asia/Kolkata")
    expect(data["group"].keys).not_to include("organization_id", "user_id", "members", "attendees", "scopes")
    expect(data["upcoming_events"].first.keys).not_to include("organization_id", "user_id", "tickets", "passes", "scopes")
    post unpublish_organizer_organization_group_path(organization, group)
    get api_path
    expect(response).to have_http_status(:not_found)
    expect(event.reload).to be_published
  end

  it "paginates upcoming and archive events independently without losing results" do
    group.update!(status: :published)
    26.times do |i|
      organization.events.create!(title: "Next #{i}", slug: "next-#{i}", status: :published, community_group: group, starts_at: (i + 1).days.from_now, ends_at: (i + 2).days.from_now)
    end
    organization.events.create!(title: "Past gathering", slug: "past", status: :published, community_group: group, starts_at: 2.days.ago, ends_at: 1.day.ago)
    get api_path
    first = response.parsed_body
    expect(first["upcoming_events"].size).to eq(24)
    expect(first["pagination"]["upcoming"]).to include("page" => 1, "total" => 26, "per_page" => 24)
    get api_path, params: { upcoming_page: 2, past_page: -1 }
    second = response.parsed_body
    expect(second["upcoming_events"].size).to eq(2)
    expect(second["past_events"].pluck("title")).to eq([ "Past gathering" ])
    expect(first["upcoming_events"].pluck("id") & second["upcoming_events"].pluck("id")).to be_empty
    get public_path, params: { past_page: 2 }
    expect(response.body).to include("upcoming_page=2", "past_page=2")
  end

  it "preserves the legacy attendee directory route" do
    expect(community_path).to eq("/community")
    expect(public_path).to eq("/communities/synthetic-ruby/pune-ruby")
  end
end
