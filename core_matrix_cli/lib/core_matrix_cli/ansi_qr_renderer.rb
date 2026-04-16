require "rqrcode"

module CoreMatrixCLI
  class AnsiQRRenderer
    def render(qr_text)
      RQRCode::QRCode.new(qr_text).as_ansi
    end
  end
end
