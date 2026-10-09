class ConferenceBadgesController < ApplicationController
  layout "conference_badges"
  prepend_before_action :private_response
  before_action :require_badge_operator

  def index
    page = params[:page].to_s
    @page = page.match?(/\A[1-9]\d{0,3}\z/) ? page.to_i : 1
    @duplicates = ConferenceBadges::Selection.duplicate_ids
    @tickets = ConferenceInventory.confirmed.select("tickets.id", "tickets.attendee_name")
      .order(Arel.sql("lower(btrim(tickets.attendee_name)) ASC NULLS LAST"), :id).limit(51).offset((@page - 1) * 50).to_a
    @more = @tickets.length > 50
    @tickets = @tickets.first(50)
  end

  def sample
    document(ConferenceBadges::Selection.sample)
  end

  def print
    companies = params[:companies]
    companies = companies.to_unsafe_h if companies.is_a?(ActionController::Parameters)
    ids = params[:ticket_ids]
    companies = companies.reject { |id, text| text == "" && !ids.map(&:to_s).include?(id.to_s) } if companies.is_a?(Hash) && ids.is_a?(Array)
    badges = ConferenceBadges::Selection.build(ids:, companies: companies || {}, confirmed: params[:confirmed])
    document(badges)
  rescue ConferenceBadges::Selection::Invalid => error
    @error = error.message
    index
    render :index, status: :unprocessable_content
  end

  private
    def document(badges)
      respond_to do |format|
        format.html { render html: ConferenceBadges::Document.preview(badges).html_safe, layout: false }
        format.pdf { send_data ConferenceBadges::Document.pdf(badges), type: "application/pdf", disposition: "inline", filename: "DQOR-conference-badges.pdf" }
      end
    end

    def require_badge_operator
      operator = Current.admin_user&.reload
      head :forbidden unless operator&.admin? || operator&.desk?
    end

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["Pragma"] = "no-cache"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'self' 'unsafe-inline'; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    end
end
