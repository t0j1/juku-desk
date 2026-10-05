class CreateMarkingUploads < ActiveRecord::Migration[8.1]
  def change
    # マーキング検出で取り込んだ教材画像（縮小済み）。画像本体は R2、ここにはキーと寸法だけ持つ
    create_table :uploads do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :sha256, null: false
      t.string :r2_key, null: false
      t.string :content_type, null: false
      t.integer :width, null: false
      t.integer :height, null: false
      t.integer :byte_size, null: false
      t.timestamps
    end
    add_index :uploads, :sha256, unique: true

    # 画像の中で赤枠が囲んでいた領域。切り出した画像は R2
    create_table :crop_regions do |t|
      t.references :upload, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :bbox, null: false, default: {}
      t.string :r2_key, null: false
      t.float :confidence
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    add_index :crop_regions, :status
  end
end
