# 小テストを作ったときの大問ごとの指示文（[{ "section" => 1, "question_type" => "reorder", "instruction" => "…" }, …]）。
# 印刷はこれを使うので、あとで大問の指示文を編集しても作成済みの小テストは変わらない。
# 既存の小テストは [] のまま（印刷ではテンプレートの指示文を使う）。
class AddSectionsToTests < ActiveRecord::Migration[8.1]
  def change
    add_column :tests, :sections, :jsonb, default: [], null: false
  end
end
