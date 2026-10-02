# Software QR decoder fallback

The existing bundled html5-qrcode ZXing adapter cannot decode the valid synthetic
QR in `spec/fixtures/checkin_software_decoder_secret.txt`. The original CI failure
was reproduced locally using that exact payload, recovered from a CI screenshot;
it is not a production ticket. Enabling ZXing TRY_HARDER also failed and was reverted.

A narrow patch in the adapter's `decode(canvas)` catches a ZXing decode failure and
passes the same canvas pixels to jsQR. It returns the existing QR result interface,
so camera frames and image uploads keep one success callback and the existing
serialization/deduplication. If neither decoder finds a QR, the original error is
preserved. It never supplies synthetic success, sends pixels off-device, or modifies
ticket payloads. The attendance scanner loads jsQR and restricts formats to QR_CODE.

jsQR 1.4.0 is vendored unchanged from its npm release, with its Apache-2.0 license.
Registry tarball: https://registry.npmjs.org/jsqr/-/jsqr-1.4.0.tgz
SHA512: dxLob7q65Xg2DvstYkRpkYtmKm2sPJ9oFhrhmudT1dZvNFFTlroai3AWSpLey/w5vMcLBXRgOJsbXpdN9HzU/A==
Upstream: https://github.com/cozmo/jsQR
No package install scripts were executed. Preserve license and this provenance when
updating. Reapply only this documented adapter fallback if replacing html5-qrcode,
and rerun the real image-decoding regression without BarcodeDetector.
