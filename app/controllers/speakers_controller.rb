class SpeakersController < ApplicationController
  allow_unauthenticated_access

  def index
    @speakers = Speaker.published.ordered
  end
end
