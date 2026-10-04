# マーキング検出の設定値。しきい値・上限はすべて環境変数から読む（コードに埋め込まない）。
# ブラウザの検出ロジックには data 属性（to_h）で配る。
module MarkingConfig
  module_function

  def float(name, default) = ENV[name].presence ? Float(ENV[name]) : default
  def int(name, default) = ENV[name].presence ? Integer(ENV[name]) : default

  def max_bytes = int("MARKING_MAX_BYTES", 5.megabytes)
  def max_regions = int("MARKING_MAX_REGIONS", 100)

  # ブラウザへ渡す設定（detector のしきい値、縮小後の長辺、余白、JPEG 品質）
  def to_h
    {
      maxLongSide: int("MARKING_MAX_LONG_SIDE", 1600),
      padding: int("MARKING_CROP_PADDING", 8),
      jpegQuality: float("MARKING_JPEG_QUALITY", 0.85),
      maxBytes: max_bytes,
      detector: {
        hueLow: int("MARKING_HUE_LOW", 10), hueHigh: int("MARKING_HUE_HIGH", 170),
        minSaturation: int("MARKING_MIN_SATURATION", 70), minValue: int("MARKING_MIN_VALUE", 50),
        closeKernel: int("MARKING_CLOSE_KERNEL", 5), closeIterations: int("MARKING_CLOSE_ITERATIONS", 2),
        openKernel: int("MARKING_OPEN_KERNEL", 3), openIterations: int("MARKING_OPEN_ITERATIONS", 1),
        minAreaRatio: float("MARKING_MIN_AREA_RATIO", 0.005), maxAreaRatio: float("MARKING_MAX_AREA_RATIO", 0.9),
        maxAspectRatio: float("MARKING_MAX_ASPECT_RATIO", 20), maxFillRatio: float("MARKING_MAX_FILL_RATIO", 0.95),
        mergeGap: int("MARKING_MERGE_GAP", 12), iouThreshold: float("MARKING_IOU_THRESHOLD", 0.5),
        tiltThreshold: float("MARKING_TILT_THRESHOLD", 0.5)
      }
    }
  end
end
