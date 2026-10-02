module Organizer
  class EventBrandingController < ApplicationController
    layout "event_branding"
    before_action :require_organizer
    before_action :private_response
    before_action :set_setting
    rescue_from EventBranding::Configuration::Invalid, ActiveRecord::RecordInvalid, with: :invalid_configuration
    rescue_from EventBrandingSetting::StaleDraft, ActiveRecord::StaleObjectError, with: :stale_configuration

    def show
      @configuration = EventBranding::Configuration.new(@setting.draft)
    end

    def update
      values = params.require(:branding)
      raise EventBranding::Configuration::Invalid, "Branding must be a configuration object" unless values.is_a?(ActionController::Parameters)
      allowed = %w[theme accent surface font sections lock_version remove_assets logo cover favicon]
      raise EventBranding::Configuration::Invalid, "Unsupported branding fields" if (values.keys - allowed).any?
      removals = values.fetch(:remove_assets, [])
      raise EventBranding::Configuration::Invalid, "Unsupported image slot" unless removals.is_a?(Array) && (removals - EventBranding::Configuration::ASSETS).empty?
      uploads = EventBranding::Configuration::ASSETS.filter_map { |slot| [ slot, values[slot] ] if values[slot].present? }.to_h
      config = { "version" => 1, "theme" => values[:theme], "accent" => values[:accent], "surface" => values[:surface], "font" => values[:font], "sections" => values[:sections] }
      @setting.save_draft!(values: config, uploads: uploads, removals: removals, expected_version: version(values[:lock_version]), actor: Current.admin_user)
      saved_response("Draft saved to the server. Published configuration is unchanged.")
    end

    def preview
      raise EventBranding::Configuration::Invalid, "Choose the saved draft or published preview" unless [ nil, "draft", "published" ].include?(params[:snapshot])
      snapshot = params[:snapshot] == "published" ? @setting.published : @setting.draft
      raise EventBranding::Configuration::Invalid, "No configuration has been published yet" unless snapshot
      @configuration = EventBranding::Configuration.new(snapshot)
      @snapshot_label = params[:snapshot] == "published" ? "Published configuration" : "Saved draft"
      render layout: false
    end

    def publish
      raise EventBranding::Configuration::Invalid, "Confirm publication of the saved draft" unless params[:confirmed] == "1"
      @setting.publish!(expected_version: version(params[:lock_version]), actor: Current.admin_user)
      saved_response("Configuration published. Public activation remains off; the live event is unchanged.")
    end

    def rollback
      raise EventBranding::Configuration::Invalid, "Confirm rollback to the previous publication" unless params[:confirmed] == "1"
      @setting.rollback!(expected_version: version(params[:lock_version]), actor: Current.admin_user)
      saved_response("Previous published configuration restored. Draft kept; public activation remains off.")
    end

    def asset
      image = @setting.assets.find(params[:id])
      response.headers["X-Content-Type-Options"] = "nosniff"
      send_data image.image_data, type: image.content_type, disposition: "inline", filename: "branding-#{image.id}.webp"
    end

    private
      def saved_response(message)
        respond_to do |format|
          format.html { redirect_to organizer_branding_path, notice: message, status: :see_other }
          format.json do
            flash[:notice] = message
            render json: { redirect: organizer_branding_path }
          end
        end
      end

      def require_organizer
        head :forbidden unless Current.admin_user&.admin?
      end

      def private_response
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["X-Robots-Tag"] = "noindex, nofollow"
      end

      def set_setting
        @setting = EventBrandingSetting.current
      end

      def version(raw)
        raise EventBranding::Configuration::Invalid, "Reload the editor to obtain its current revision" unless raw.to_s.match?(/\A\d+\z/)
        raw.to_i
      end

      def invalid_configuration(error)
        @error = error.message
        return render json: { error: @error }, status: :unprocessable_entity if request.format.json?
        @configuration = EventBranding::Configuration.new(@setting.reload.draft)
        render :show, status: :unprocessable_entity
      end

      def stale_configuration(error)
        @error = error.message
        return render json: { error: @error }, status: :conflict if request.format.json?
        @configuration = EventBranding::Configuration.new(@setting.reload.draft)
        render :show, status: :conflict
      end
  end
end
