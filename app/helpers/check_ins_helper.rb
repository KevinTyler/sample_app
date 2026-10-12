module CheckInsHelper
  # QR code (as a PNG data URI, which the CSP allows) for a guest's check-in pass.
  def check_in_qr_data_uri(guest)
    url = event_check_in_scan_url(guest.event, code: guest.check_in_code)
    RQRCode::QRCode.new(url, level: :m).as_png(size: 240, border_modules: 2).to_data_url
  end
end
