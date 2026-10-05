class CreatePrintSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :print_schedules do |t|
      t.string :name, null: false
      t.references :print_station, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.integer :copies, null: false, default: 1
      t.boolean :collate, null: false, default: true
      t.string :staple
      t.string :driver_preset
      t.integer :weekdays, array: true, null: false, default: [] # 0=日 … 6=土（Ruby の wday）
      t.string :time_of_day, null: false # "HH:MM"（Asia/Tokyo）
      t.boolean :active, null: false, default: true
      t.string :r2_key
      t.binary :pdf_data # PDF_STORAGE=db のとき
      t.string :sha256, null: false
      t.integer :byte_size, null: false
      t.timestamps
    end
    add_index :print_schedules, :r2_key, unique: true

    # 雛形から作ったジョブ。雛形を消してもジョブの履歴は残す。同じ雛形・同じ日のジョブは 1 件まで（定期ジョブの再実行で二重に作らない）
    add_reference :print_jobs, :print_schedule, foreign_key: { on_delete: :nullify }
    add_column :print_jobs, :scheduled_for, :date
    add_index :print_jobs, %i[ print_schedule_id scheduled_for ], unique: true, where: "print_schedule_id IS NOT NULL", name: "index_print_jobs_on_schedule_and_day"
    add_index :print_jobs, :scheduled_for
  end
end
