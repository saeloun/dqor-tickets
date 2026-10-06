class Organizer::EventWebsitesController < Organizer::BaseController
  layout "event_website_editor"
  prepend_before_action :private_response
  before_action :set_event
  before_action :require_event_manager, only: %i[update publish restore]
  before_action :set_setting
  rescue_from EventWebsites::Configuration::Invalid, ActiveRecord::RecordInvalid, with: :invalid_configuration
  rescue_from EventWebsiteSetting::StaleDraft, ActiveRecord::StaleObjectError, with: :stale_configuration
  rescue_from EventWebsiteSetting::AccessDenied, with: :access_denied

  def show
    @configuration = EventWebsites::Configuration.new(@setting.draft)
  end

  def update
    input = params.require(:website)
    raise EventWebsites::Configuration::Invalid, "Website must be a configuration object" unless input.is_a?(ActionController::Parameters)
    allowed = EventWebsites::Configuration::KEYS - %w[version assets] + %w[lock_version remove_assets logo cover favicon]
    raise EventWebsites::Configuration::Invalid, "Unsupported website fields" if (input.keys - allowed).any?
    values = input.slice(*(EventWebsites::Configuration::KEYS - %w[version assets])).to_unsafe_h
    values["version"] = EventWebsites::Configuration::VERSION
    values["sections"] = targets(input[:sections])
    values["navigation"] = targets(input[:navigation])
    values["programme"] = entries(input[:programme], EventWebsites::Configuration::PROGRAMME_LIMITS)
    values["sponsors"] = entries(input[:sponsors], EventWebsites::Configuration::SPONSOR_LIMITS)
    uploads = EventWebsites::Configuration::ASSETS.filter_map { |slot| [ slot, input[slot] ] if input[slot].present? }.to_h
    removals = input.fetch(:remove_assets, [])
    @setting.save_draft!(values:, uploads:, removals:, expected_version: version(input[:lock_version]), actor: current_user)
    redirect_to organizer_organization_event_website_path(@organization, @event), notice: "Draft saved. Your public website is unchanged.", status: :see_other
  end

  def preview
    raise EventWebsites::Configuration::Invalid, "Choose a saved draft or publication" unless [ nil, "draft", "published", "previous" ].include?(params[:snapshot])
    snapshot = case params[:snapshot]
    when "published" then @setting.published
    when "previous" then @setting.previous_published
    else @setting.draft
    end
    raise EventWebsites::Configuration::Invalid, "That publication is not available" unless snapshot
    @configuration = EventWebsites::Configuration.new(snapshot)
    @website_preview = true
    @free_types = []
    render "event_websites/show", layout: "event_website"
  end

  def publish
    confirm!("Publish the saved draft")
    @setting.publish!(expected_version: version(params[:lock_version]), actor: current_user)
    redirect_to organizer_organization_event_website_path(@organization, @event), notice: "Website published for this event.", status: :see_other
  end

  def restore
    confirm!("Restore the previous publication")
    @setting.restore!(expected_version: version(params[:lock_version]), actor: current_user)
    redirect_to organizer_organization_event_website_path(@organization, @event), notice: "Previous publication restored. Your saved draft is unchanged.", status: :see_other
  end

  def asset
    raise ActiveRecord::RecordNotFound unless params[:asset_id].to_s.match?(/\A[1-9]\d{0,18}\z/) && params[:asset_id].to_i <= 9_223_372_036_854_775_807
    image = @setting.assets.find(params[:asset_id])
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data image.image_data, type: image.content_type, disposition: "inline", filename: "event-website-#{image.id}.webp"
  end

  private
    def set_event
      @event = @organization.events.find(params[:event_id])
    end

    def set_setting
      @setting = EventWebsiteSetting.for_event(@event)
    end

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end

    def targets(raw)
      return [] if raw.nil?
      raise EventWebsites::Configuration::Invalid, "Choose supported website sections" unless raw.is_a?(Array) && raw.size <= EventWebsites::Configuration::SECTIONS.size
      raw.reject { |target| target == "" }
    end

    def entries(raw, limits)
      return [] if raw.nil?
      raise EventWebsites::Configuration::Invalid, "Use up to 20 manual entries" unless raw.is_a?(Array) && raw.size <= 20
      raw.filter_map do |entry|
        raise EventWebsites::Configuration::Invalid, "Unsupported manual entry fields" unless entry.is_a?(ActionController::Parameters) && entry.keys.sort == limits.keys.sort
        values = entry.to_unsafe_h
        values unless values.values.all? { |value| value == "" }
      end
    end

    def version(raw)
      raise EventWebsites::Configuration::Invalid, "Reload the editor to obtain its current revision" unless raw.to_s.match?(/\A\d{1,10}\z/)
      raw.to_i
    end

    def confirm!(message)
      raise EventWebsites::Configuration::Invalid, "#{message} by checking its confirmation" unless params[:confirmed] == "1"
    end

    def invalid_configuration(error)
      @error = error.message
      set_setting
      @configuration = EventWebsites::Configuration.new(@setting.draft)
      render :show, status: :unprocessable_content
    end

    def stale_configuration(error)
      @error = error.message
      set_setting
      @configuration = EventWebsites::Configuration.new(@setting.draft)
      render :show, status: :conflict
    end

    def access_denied
      head :forbidden
    end
end
