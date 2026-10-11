module WallOfLoveHelper
  def wall_love_source_url(value)
    WallLoveNote.safe_source_url(value)
  end
end
