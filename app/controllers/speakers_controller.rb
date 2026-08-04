class SpeakersController < ApplicationController
  allow_unauthenticated_access

  def index
    @speakers = Speaker.publicly_listed.ordered.includes(:talks)
  end

  def show
    @speaker = Speaker.publicly_listed.find(params[:id])
  end
end
