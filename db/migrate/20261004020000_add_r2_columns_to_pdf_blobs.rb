# PDF 本体を R2 に置けるようにする。r2_key があれば R2 に実体がある（＝移行済み）。
# data は R2 に移したあと purge できるよう NULL を許す（purge は別タスク pdf_blobs:purge_db_copies）。
class AddR2ColumnsToPdfBlobs < ActiveRecord::Migration[8.1]
  def up
    add_column :pdf_blobs, :r2_key, :string
    add_column :pdf_blobs, :checksum, :string # 本体の SHA-256（hex）
    add_column :pdf_blobs, :r2_migrated_at, :datetime
    add_index :pdf_blobs, :r2_key, unique: true
    change_column_null :pdf_blobs, :data, true
  end

  def down
    if select_value("SELECT 1 FROM pdf_blobs WHERE data IS NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "data が NULL の行があります（R2 にしか無いデータは戻せません）。先に PDF_STORAGE=db へ戻して取り込み直してください"
    end
    change_column_null :pdf_blobs, :data, false
    remove_index :pdf_blobs, :r2_key
    remove_column :pdf_blobs, :r2_migrated_at
    remove_column :pdf_blobs, :checksum
    remove_column :pdf_blobs, :r2_key
  end
end
