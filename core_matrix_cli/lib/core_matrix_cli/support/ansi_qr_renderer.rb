require "rqrcode"

module CoreMatrixCLI
  module Support
    class AnsiQrRenderer
      def render(qr_text)
        RQRCode::QRCode.new(qr_text).as_ansi
      end
    end
  end
end
