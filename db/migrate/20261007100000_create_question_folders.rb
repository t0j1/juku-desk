# 問題フォルダ（名前付き）。複数の取り込み画像をまとめて、フォルダ内の全画像の問題から 1 枚のプリントを作る。
# 1 枚の画像は複数のフォルダに入れてよい。フォルダを消しても画像・問題は消えない（紐づけだけが消える）。
class CreateQuestionFolders < ActiveRecord::Migration[8.1]
  def change
    create_table :question_folders do |t|
      t.string :name, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    create_table :question_folder_uploads do |t|
      t.references :question_folder, null: false, foreign_key: { on_delete: :cascade }
      t.references :upload, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :question_folder_uploads, %i[ question_folder_id upload_id ], unique: true
  end
end
