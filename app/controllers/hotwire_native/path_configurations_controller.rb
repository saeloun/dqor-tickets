module HotwireNative
  class PathConfigurationsController < ApplicationController
    allow_unauthenticated_access

    PATH_CONFIGURATION = {
      settings: { screenshots_enabled: true },
      rules: [
        { patterns: [ "/new$", "/edit$" ], properties: { context: "modal" } },
        { patterns: [ "/login", "/session/new", "/user/magic-link", "/passwords" ], properties: { context: "modal" } },
        { patterns: [ "/checkin" ], properties: { context: "default", pull_to_refresh_enabled: false } },
        { patterns: [ ".*" ], properties: { context: "default", pull_to_refresh_enabled: true } }
      ]
    }.freeze

    def show
      render json: PATH_CONFIGURATION
    end
  end
end
