# 1日のスケジュールの定時タスク（印刷する／書類の原案を作る）と、その実行履歴
class CreateDailyScheduleTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_schedule_tasks do |t|
      t.string :name, null: false
      t.string :execution_time, null: false # HH:MM（Asia/Tokyo）
      t.string :repeat_type, null: false # daily / weekdays / custom / once
      t.integer :custom_weekdays, array: true, default: [], null: false # 0=日 … 6=土（custom のとき）
      t.date :once_date # once のとき
      t.string :execution_type, null: false # print / create_draft
      t.boolean :enabled, default: true, null: false
      t.references :created_by, foreign_key: { to_table: :users }
      # 印刷する
      t.references :print_station, foreign_key: true
      # トレイは未対応（印刷エージェントは driver_preset 経由で扱うため）。必要になったら追加する
      t.string :duplex # long / short / NULL
      t.integer :copies, default: 1, null: false
      t.string :r2_key
      t.binary :pdf_data
      t.string :sha256
      t.integer :byte_size
      # 書類の原案を作成する（テンプレートの種類は確認中のため、仮の一覧から選ぶ）
      t.string :template_key
      t.string :save_destination
      t.timestamps
    end
    add_index :daily_schedule_tasks, :r2_key, unique: true

    create_table :daily_schedule_executions do |t|
      t.references :daily_schedule_task, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false # 予定時刻
      t.datetime :executed_at # 実際に動いた（または判断した）時刻
      t.string :status, null: false # executed / draft_saved / skipped / failed / not_run
      t.text :message
      t.references :print_job, foreign_key: true
      t.text :draft_text # 保存した原案（下書き）
      t.timestamps
    end
    # 同じ予定時刻の実行は 1 回だけ（再実行しない）
    add_index :daily_schedule_executions, %i[ daily_schedule_task_id scheduled_at ], unique: true, name: "index_daily_schedule_executions_once"
  end
end
