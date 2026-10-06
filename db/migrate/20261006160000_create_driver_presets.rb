# ドライバー設定名（プリンタードライバーに保存した印刷設定の名前）の一覧。画面ではここからプルダウンで選ぶ。
# 自由入力だと誤入力（例：「デフォルト」）で、エージェントが存在しないプリンター名を探し続けるため。
# ステーション別にしないのは、設定名は校舎で共通の名前にそろえて運用しており、画面でステーションを選ぶ前にも選択肢が要るため。
class CreateDriverPresets < ActiveRecord::Migration[8.1]
  def up
    create_table :driver_presets do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :driver_presets, :name, unique: true
    execute "INSERT INTO driver_presets (name, created_at, updated_at) VALUES ('bizhub-551i-staple-duplex-tray2', NOW(), NOW())"
  end

  def down
    drop_table :driver_presets
  end
end
