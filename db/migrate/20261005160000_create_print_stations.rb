class CreatePrintStations < ActiveRecord::Migration[8.1]
  def change
    # 教室PCに常駐する自動印刷エージェント。トークンは生では持たず、SHA-256 のダイジェストだけ保存する
    create_table :print_stations do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :token_issued_at, null: false
      t.datetime :revoked_at
      t.datetime :last_seen_at
      t.string :agent_version
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :print_stations, :token_digest, unique: true
  end
end
