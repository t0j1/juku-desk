module QrHelper
  # viewbox: true にすると width/height の代わりに viewBox を出す（CSS でサイズを決める画面向け）
  def qr_svg(url, module_size: 4, viewbox: false)
    RQRCode::QRCode.new(url).as_svg(color: "000", shape_rendering: "crispEdges", module_size:, standalone: true, use_path: true, viewbox:).html_safe # rubocop:disable Rails/OutputSafety
  end
end
