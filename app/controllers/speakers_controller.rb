class SpeakersController < ApplicationController
  allow_unauthenticated_access

  def index
    @speakers = Speaker.published.ordered.includes(:talks)
  end

  def show
    @speaker = Speaker.published.find(params[:id])
  end
end
