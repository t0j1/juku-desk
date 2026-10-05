class CreateQuestionsAndGeminiQuota < ActiveRecord::Migration[8.1]
  def change
    # Gemini が領域の画像から作った問題。レビューで承認（reviewed_at）されたものだけが出題対象
    create_table :questions do |t|
      t.references :region, null: false, foreign_key: { to_table: :crop_regions, on_delete: :cascade }, index: { unique: true }
      t.string :subject
      t.text :question_text, null: false, default: ""
      t.jsonb :options, null: false, default: []
      t.text :answer_text, null: false, default: ""
      t.text :explanation, null: false, default: ""
      t.text :tags, array: true, null: false, default: []
      t.integer :difficulty
      t.jsonb :raw_ai, null: false, default: {}
      t.datetime :reviewed_at
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :questions, :tags, using: :gin
    add_index :questions, :subject
    add_index :questions, :reviewed_at
    add_check_constraint :questions, "difficulty IS NULL OR difficulty BETWEEN 1 AND 5", name: "questions_difficulty_range"

    # 将来の弱点出題用（今回は記録しない）
    create_table :answer_events do |t|
      t.references :question, null: false, foreign_key: { on_delete: :cascade }
      t.references :student, foreign_key: { on_delete: :nullify }
      t.boolean :correct
      t.datetime :answered_at
      t.timestamps
    end

    add_column :crop_regions, :error_message, :text
    add_column :crop_regions, :extracted_at, :datetime

    # Gemini の RPM（トークンバケット）・RPD（太平洋時間の日次カウンタ）・日次上限の保留状態。全プロセスで 1 行を共有する
    create_table :gemini_quotas do |t|
      t.float :tokens, null: false, default: 1.0
      t.datetime :refilled_at
      t.date :day
      t.integer :day_count, null: false, default: 0
      t.datetime :exceeded_at
      t.datetime :resume_at
      t.timestamps
    end
  end
end
