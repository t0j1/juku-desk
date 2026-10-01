module QrHelper
  def qr_svg(url, module_size: 4)
    RQRCode::QRCode.new(url).as_svg(color: "000", shape_rendering: "crispEdges", module_size:, standalone: true, use_path: true).html_safe # rubocop:disable Rails/OutputSafety
  end
end
