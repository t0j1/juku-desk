# PrintPreset の初期データ。db:seed で実行される。
# 開発・テスト・本番すべてで同じプリセット名が使えるようにする。
module PrintPresetSeed
  INITIAL_PRESETS = [
    "bizhub-551i-staple-duplex-tray2"
  ].freeze

  def self.run
    INITIAL_PRESETS.each do |name|
      PrintPreset.find_or_create_by!(name: name)
    end
  end
end

PrintPresetSeed.run
