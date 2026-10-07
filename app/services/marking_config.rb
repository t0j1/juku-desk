# マーキング検出の設定値。しきい値・上限はすべて環境変数から読む（コードに埋め込まない）。
# ブラウザの検出ロジックには data 属性（to_h）で配る。
module MarkingConfig
  module_function

  def float(name, default) = ENV[name].presence ? Float(ENV[name]) : default
  def int(name, default) = ENV[name].presence ? Integer(ENV[name]) : default

  def max_bytes = int("MARKING_MAX_BYTES", 5.megabytes)
  def max_regions = int("MARKING_MAX_REGIONS", 100)
  # 問題フォルダ画面から端末のファイル・PDF を直接入れるときの上限（PDF は 1 ファイルあたり。選択は 1 回あたり）
  def pdf_max_bytes = int("MARKING_PDF_MAX_BYTES", 20.megabytes)
  def pdf_max_pages = int("MARKING_PDF_MAX_PAGES", 50)
  def max_files = int("MARKING_MAX_FILES", 30)

  # ブラウザへ渡す設定（detector のしきい値、縮小後の長辺、余白、JPEG 品質）
  # 余白は赤枠の外側に足す px（縮小後の画像で）。8px だと問題の間隔が詰まった教材で隣の問題の上端が写り込むので 4px にした
  def to_h
    {
      maxLongSide: int("MARKING_MAX_LONG_SIDE", 1600),
      padding: int("MARKING_CROP_PADDING", 4),
      jpegQuality: float("MARKING_JPEG_QUALITY", 0.85),
      maxBytes: max_bytes,
      pdfMaxBytes: pdf_max_bytes,
      pdfMaxPages: pdf_max_pages,
      maxFiles: max_files,
      detector: {
        hueLow: int("MARKING_HUE_LOW", 10), hueHigh: int("MARKING_HUE_HIGH", 170),
        minSaturation: int("MARKING_MIN_SATURATION", 70), minValue: int("MARKING_MIN_VALUE", 50),
        closeKernel: int("MARKING_CLOSE_KERNEL", 5), closeIterations: int("MARKING_CLOSE_ITERATIONS", 2),
        openKernel: int("MARKING_OPEN_KERNEL", 3), openIterations: int("MARKING_OPEN_ITERATIONS", 1),
        minAreaRatio: float("MARKING_MIN_AREA_RATIO", 0.005), maxAreaRatio: float("MARKING_MAX_AREA_RATIO", 0.9),
        maxAspectRatio: float("MARKING_MAX_ASPECT_RATIO", 20), maxFillRatio: float("MARKING_MAX_FILL_RATIO", 0.95),
        maxInnerFillRatio: float("MARKING_MAX_INNER_FILL_RATIO", 0.3), edgeMargin: int("MARKING_EDGE_MARGIN", 4), tabAspectRatio: float("MARKING_TAB_ASPECT_RATIO", 3),
        mergeGap: int("MARKING_MERGE_GAP", 12), iouThreshold: float("MARKING_IOU_THRESHOLD", 0.5),
        tiltThreshold: float("MARKING_TILT_THRESHOLD", 0.5)
      }
    }
  end
end
