class TeamController < ApplicationController
  allow_unauthenticated_access

  def index
    @team_members = TeamMember.publicly_listed.ordered
  end
end
