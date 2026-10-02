import "jsqr"
import "html5-qrcode"

// Shared by admission, slot redemption, and the isolated synthetic rehearsal.
export function initializeCamera(host, readerId, fallback) {
  host.cameraInterrupted = false
  const Scanner = window.__Html5QrcodeLibrary__?.Html5QrcodeScanner
  if (!Scanner || !window.isSecureContext) {
    host.cameraStatusTarget.textContent = `${Scanner ? "Camera requires HTTPS" : "Camera scanner unavailable"}. ${fallback}`
    return
  }
  host.scanner = new Scanner(readerId, {
    fps: 10, rememberLastUsedCamera: false, useBarCodeDetectorIfSupported: false,
    formatsToSupport: [window.__Html5QrcodeLibrary__.Html5QrcodeSupportedFormats.QR_CODE],
    qrbox: (width, height) => { const side = Math.min(250, Math.floor(Math.min(width, height) * 0.7)); return { width: side, height: side } }
  }, false)
  host.scanner.render(secret => host.scan(secret), () => {})
}

export function interruptCamera(host, fallback) {
  host.cameraInterrupted = true
  try { host.scanner?.pause(true) } catch (_) {}
  host.cameraStatusTarget.textContent = `Camera paused after leaving the page or rotating your phone. Tap Restart camera, then choose the back/rear camera. ${fallback}`
}

export async function restartCamera(host, guidance, resetLastSecret = false) {
  if (host.busy) return
  try { await host.scanner?.clear() } catch (_) {}
  if (!host.connected) return
  host.scanner = null
  if (resetLastSecret) host.lastSecret = null
  host.initializeScanner()
  host.cameraStatusTarget.textContent = guidance
}
