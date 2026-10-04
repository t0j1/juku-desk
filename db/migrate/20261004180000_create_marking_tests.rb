class CreateMarkingTests < ActiveRecord::Migration[8.1]
  def change
    # マーキング由来の問題（承認済み）から作った小テスト。filter は出題条件と、条件に合った問題の数（不足の表示用）
    create_table :tests do |t|
      t.string :title, null: false
      t.string :mode, null: false
      t.string :subject
      t.jsonb :filter, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_check_constraint :tests, "mode IN ('random', 'by_tag')", name: "tests_mode_values"

    create_table :test_items do |t|
      t.references :test, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :question, null: false, foreign_key: { on_delete: :restrict }
      t.integer :position, null: false
      t.timestamps
    end
    add_index :test_items, %i[test_id position], unique: true
    add_index :test_items, %i[test_id question_id], unique: true
  end
end
