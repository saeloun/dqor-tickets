require "rails_helper"

RSpec.describe "Avo missing associations", type: :request do
  let!(:speaker) { Speaker.create!(name: "Synthetic stale-route speaker") }
  let!(:talk) { Talk.create!(title: "Synthetic associated talk", speaker:) }

  def missing_routes
    [
      [ :get, "/avo/resources/speakers/#{speaker.id}/talk" ],
      [ :get, "/avo/resources/speakers/#{speaker.id}/talk/#{talk.id}" ],
      [ :get, "/avo/resources/speakers/#{speaker.id}/talk/new" ],
      [ :post, "/avo/resources/speakers/#{speaker.id}/talk" ],
      [ :delete, "/avo/resources/speakers/#{speaker.id}/talk/#{talk.id}" ]
    ]
  end

  it "returns not found for every routed stale singular talk association action without changing records" do
    sign_in_admin
    original_speaker = speaker.attributes
    original_talk = talk.attributes

    expect {
      missing_routes.each do |method, route|
        public_send(method, route, params: method == :post ? { fields: { related_id: talk.id } } : {})
        expect(response).to have_http_status(:not_found)
        expect(response.body).to be_empty
      end
    }.not_to change { [ Speaker.count, Talk.count ] }

    expect(speaker.reload.attributes).to eq(original_speaker)
    expect(talk.reload.attributes).to eq(original_talk)
  end

  it "does not make unconfigured plural associations or ordinary fields navigable" do
    sign_in_admin
    %w[talks name].each do |association|
      get "/avo/resources/speakers/#{speaker.id}/#{association}"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "renders the configured order-ticket association with its actual data" do
    order = create(:order, :paid)
    ticket = create(:ticket, order:, attendee_name: "Synthetic supported association attendee")
    sign_in_admin

    get "/avo/resources/orders/#{order.id}/tickets"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ticket.attendee_name)
  end

  it "installs the guard once when prepare callbacks repeat and keeps configured associations working" do
    2.times { Rails.application.reloader.prepare! }
    expect(Avo::AssociationsController.ancestors.count(AvoMissingAssociation)).to eq(1)
    order = create(:order, :paid)
    ticket = create(:ticket, order:, attendee_name: "Synthetic prepared association attendee")
    sign_in_admin

    get "/avo/resources/speakers/#{speaker.id}/talk"
    expect(response).to have_http_status(:not_found)
    get "/avo/resources/orders/#{order.id}/tickets"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ticket.attendee_name)
  end

  it "authenticates anonymous requests before resolving each missing association action" do
    missing_routes.each do |method, route|
      public_send(method, route, params: method == :post ? { fields: { related_id: talk.id } } : {})
      expect(response).to redirect_to("/session/new")
    end
  end

  it "keeps desk staff restricted before resolving each missing association action" do
    sign_in_admin(create(:admin_user, role: :desk, password: "password123"))
    missing_routes.each do |method, route|
      public_send(method, route, params: method == :post ? { fields: { related_id: talk.id } } : {})
      expect(response).to redirect_to("/checkin")
    end
  end
end
