module Api
  module Public
    module V1
      class ProgrammesController < ActionController::API
        def show
          payload = PublicProgramme::Snapshot.call
          response.headers["Cache-Control"] = "public, max-age=0, must-revalidate"
          render json: payload if stale?(etag: payload.fetch(:content_version), public: true)
        rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::StatementInvalid
          response.headers["Cache-Control"] = "no-store"
          response.headers.delete("ETag")
          render json: { schema_version: 1, error: { code: "programme_unavailable", message: "Programme temporarily unavailable. Try again later." } }, status: :service_unavailable
        end
      end
    end
  end
end
