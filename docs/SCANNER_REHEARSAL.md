# Staff camera rehearsal

Existing admin/desk staff can open `/scanner_rehearsal` from admission or scan-purpose
selection. This is a synthetic self-test, never an admission or redemption. It has no
real ticket lookup, date selection, slot configuration, result persistence, or native
API activation. The only accepted value is `DQOR-CAMERA-SELF-TEST-V1`; other contents
are rejected locally without displaying a ticket identity.

Admission, slot scanning, and rehearsal share `scanning/camera` setup, software
QR decoder (ZXing plus local jsQR fallback), interruption and explicit restart.
Rehearsal has a separate controller with no mutation/request methods. Its full-page
navigation applies `Content-Security-Policy: connect-src 'none'`, blocking fetch/XHR,
WebSockets and beacons. Camera/image pixels stay in the browser. Normal initial page
and asset loads still use the network; leaving rehearsal and signing out are explicit
navigation. Image-file reads use local blob URLs.

## Physical-device acceptance

With an existing authorized staff session, open the page on iPhone Safari and Android
Chrome over HTTPS. Show its synthetic QR on another screen or print it:

1. Request permission deliberately, choose the rear camera, and scan the sample.
   Expect the conspicuous SELF-TEST result, never a production admission message.
2. Rotate and scan: recovery must require Restart camera. Switch to another app,
   return, restart, and rescan. Verify the camera also releases when leaving the page.
3. Deny permission when prompted; synthetic manual entry must remain usable. Restore
   camera permission in browser settings and retry. No real ticket is needed.
4. Image-file upload tests the decoder; manual entry tests only the fallback UI.
   Neither proves that the physical rear camera focuses or recovers correctly.

Record device/OS/browser, permission outcome, rear-camera scan, rotation/background
recovery and manual fallback results. No attendee data or QR secrets should be included.

Automated Chromium tests cover actual software image decoding, rejection of a real
fixture ticket, simulated denial and interruption, no request attempts/no attendance
or redemption writes, and CSP blocking an accidental admission request. WebKit mobile
emulation is a separate local check, not physical iPhone certification. Real-device
checks remain required before claiming hardware readiness. Production activation and
release approval remain with the parent task; slot dates/entitlements remain unresolved.

Local validation on 2026-10-02 also passed with Playwright 1.58.2 / WebKit revision
2248 at a 390×844 mobile viewport: actual image decoding, rotation/restart, simulated
permission denial, manual fallback, zero HTTP requests during rehearsal, and CSP
blocking fetch. This used the installed macOS WebKit runtime, not an iPhone camera.
