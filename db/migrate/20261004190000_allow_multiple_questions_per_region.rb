# 1 つの赤枠に〔1〕〔2〕のように複数の問題が入っていることがあるため、1 領域から複数の questions を作れるようにする。
# 問題番号（〔1〕など）は question_text に含めず source_label に入れる。
class AllowMultipleQuestionsPerRegion < ActiveRecord::Migration[8.1]
  def change
    remove_index :questions, :region_id, unique: true
    add_index :questions, :region_id
    add_column :questions, :source_label, :string
  end
end
