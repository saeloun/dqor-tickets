export function loadWidgets() {
  if (window.twttr?.widgets?.createTweet) return Promise.resolve(window.twttr.widgets)
  if (window.dqorWallLoveWidgets) return window.dqorWallLoveWidgets
  window.dqorWallLoveWidgets = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    const timeout = window.setTimeout(() => { script.remove(); window.dqorWallLoveWidgets = null; reject(new Error("Post preview timed out")) }, 10000)
    script.src = "https://platform.twitter.com/widgets.js"
    script.async = true
    script.referrerPolicy = "no-referrer"
    script.onload = () => {
      window.clearTimeout(timeout)
      if (window.twttr?.widgets?.createTweet) resolve(window.twttr.widgets)
      else { window.dqorWallLoveWidgets = null; reject(new Error("Post preview unavailable")) }
    }
    script.onerror = () => { script.remove(); window.clearTimeout(timeout); window.dqorWallLoveWidgets = null; reject(new Error("Post preview unavailable")) }
    document.head.appendChild(script)
  })
  return window.dqorWallLoveWidgets
}

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
