# ステーション（教室PC）ごとの既定のドライバー設定名。ジョブの driver_preset が空なら、これで補う。
# 印刷エージェントは driver_preset が空だと「driver_preset is required」で失敗するため。
class AddDefaultDriverPresetToPrintStations < ActiveRecord::Migration[8.1]
  def change
    add_column :print_stations, :default_driver_preset, :string
  end
end
