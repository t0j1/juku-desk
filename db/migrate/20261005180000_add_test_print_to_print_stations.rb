class AddTestPrintToPrintStations < ActiveRecord::Migration[8.1]
  def change
    add_column :print_stations, :test_print_job_id, :bigint # 直近のテスト印刷のジョブ（履歴なので外部キーは付けない）
    add_column :print_stations, :test_print_result, :jsonb, null: false, default: {} # { tray, duplex, staple, answered_at }
  end
end
