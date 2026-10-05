class CreatePrintJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :print_jobs do |t|
      t.references :print_station, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.integer :status, null: false, default: 0
      t.datetime :scheduled_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :lease_until
      t.integer :lease_count, null: false, default: 0
      t.integer :copies, null: false, default: 1
      t.boolean :collate, null: false, default: true
      t.string :staple # 表示用。実際の設定は driver_preset（ドライバーの印刷設定名）
      t.string :driver_preset
      t.string :r2_key
      t.binary :pdf_data # PDF_STORAGE=db のとき
      t.string :sha256, null: false
      t.integer :byte_size, null: false
      t.text :result_message
      t.datetime :finished_at
      t.timestamps
    end
    add_index :print_jobs, [ :print_station_id, :status, :scheduled_at ]
    add_index :print_jobs, :r2_key, unique: true
  end
end
