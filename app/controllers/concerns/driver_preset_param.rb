# フォームの driver_preset（プルダウン）と driver_preset_new（新しく追加する名前）を、保存してよい値にする。
# 不正なら ArgumentError（各コントローラーが画面にエラーとして出す）
module DriverPresetParam
  extend ActiveSupport::Concern

  private
    def resolved_driver_preset(scope, field: :driver_preset, keep: nil)
      raw = params.fetch(scope, {})
      DriverPreset.resolve(raw[field], raw[:"#{field}_new"], keep: keep)
    end

    # 更新用: フォームに項目が無いとき（別の画面からの更新など）は、いまの値を変えない（空にしない）
    def driver_preset_attrs(scope, keep: nil)
      return {} unless params.fetch(scope, {}).key?(:driver_preset)

      { driver_preset: resolved_driver_preset(scope, keep: keep) }
    end
end
