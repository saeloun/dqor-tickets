class ScannerRehearsalsController < ApplicationController
  layout "checkin"
  TEST_QR = "DQOR-CAMERA-SELF-TEST-V1".freeze

  def show
    return head :forbidden unless Current.admin_user&.admin? || Current.admin_user&.desk?

    response.headers["Cache-Control"] = "no-store"
    # Rehearsal has no API calls, including attendance, redemption, or telemetry.
    response.headers["Content-Security-Policy"] = "connect-src 'none'"
    @qr_svg = RQRCode::QRCode.new(TEST_QR).as_svg(module_size: 6, standalone: true, use_path: true)
  end
end
