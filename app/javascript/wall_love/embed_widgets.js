export function recordingIframe(id, author) {
  if (!/^[A-Za-z0-9_-]{11}$/.test(id || "")) return null
  const iframe = document.createElement("iframe")
  iframe.src = `https://www.youtube-nocookie.com/embed/${id}?controls=1&autoplay=0&playsinline=1&rel=0`
  iframe.title = `Official recording: ${author}`
  iframe.allow = "fullscreen; picture-in-picture"
  iframe.allowFullscreen = true
  iframe.referrerPolicy = "strict-origin-when-cross-origin"
  return iframe
}
