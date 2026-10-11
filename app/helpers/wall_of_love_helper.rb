module WallOfLoveHelper
  def wall_love_embed_ids(source)
    mode = source.fetch("embed").fetch("mode")
    return {} unless mode == "official_embed_optional" || (source.fetch("platform") == "YouTube" && mode == "official_embed")

    uri = URI.parse(source.fetch("url"))
    return {} unless uri.scheme == "https" && uri.userinfo.nil?

    if source.fetch("platform") == "X" && uri.host == "x.com"
      match = uri.path.match(%r{\A/[A-Za-z0-9_]+/status/(\d{15,24})\z})
      match ? { post_id: match[1] } : {}
    elsif source.fetch("platform") == "YouTube" && uri.host == "www.youtube.com" && uri.path == "/watch"
      id = URI.decode_www_form(uri.query.to_s).to_h["v"]
      id&.match?(/\A[A-Za-z0-9_-]{11}\z/) ? { video_id: id } : {}
    else
      {}
    end
  rescue URI::InvalidURIError, ArgumentError
    {}
  end

  def wall_love_recording_preview_url(source)
    id = wall_love_embed_ids(source)[:video_id]
    "https://i.ytimg.com/vi/#{id}/hqdefault.jpg" if id
  end

  def wall_love_source_url(value)
    WallLoveNote.safe_source_url(value)
  end
end
