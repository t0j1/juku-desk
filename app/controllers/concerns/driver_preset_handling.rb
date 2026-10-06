# driver_preset パラメータの処理を共通化する concern
# 「新しく追加する」(__new__) が選ばれたとき、入力された名前で PrintPreset を作成し、
# その名前を driver_preset として返す。一覧にない名前が直接送られたときは拒否する。
module DriverPresetHandling
  extend ActiveSupport::Concern

  private

  # params から driver_preset を取り出し、正規化して返す
  # 戻り値: [正規化された driver_preset (String または nil), エラーメッセージ (String または nil)]
  def resolve_driver_preset(param_key = :driver_preset)
    raw = params.dig(param_key).to_s.strip
    return [nil, nil] if raw.blank?

    # 隠しフィールド経由で新しい名前が送られてきた場合（__new__ 選択後の入力）
    if raw != "__new__"
      # 既存のプリセット名か、新規追加された名前なら許可
      if PrintPreset.exists?(name: raw)
        return [raw, nil]
      else
        # 一覧にない名前が直接送られた → 拒否（「新しく追加する」経由のみ許可）
        return [nil, "そのプリセット名は登録されていません。「新しく追加する」から追加してください。"]
      end
    end

    # __new__ が選ばれたが、入力欄の値は hidden_field 経由で別途送られる想定
    # ここでは nil を返して、呼び出し側で hidden_field の値を見るようにする
    [nil, nil]
  end

  # test_print など、ネストしたパラメータの場合
  def resolve_driver_preset_from_nested(nested_key, param_key = :driver_preset)
    raw = params.dig(nested_key, param_key).to_s.strip
    return [nil, nil] if raw.blank?

    if raw != "__new__"
      if PrintPreset.exists?(name: raw)
        return [raw, nil]
      else
        return [nil, "そのプリセット名は登録されていません。「新しく追加する」から追加してください。"]
      end
    end

    [nil, nil]
  end

  # 新しいプリセット名が hidden_field に入っている場合に処理する
  def process_new_preset_if_any(param_key = :driver_preset)
    raw = params.dig(param_key).to_s.strip
    return nil if raw.blank? || raw == "__new__"

    # 新しいプリセット名として追加を試みる
    PrintPreset.add_new!(raw)
    raw
  rescue ArgumentError => e
    # 重複・空文字・100文字超など → 既に存在する場合はそのまま使う
    if PrintPreset.exists?(name: raw)
      raw
    else
      raise
    end
  end
end
