# 英語の問題形式（並べ替え・和訳・英作文・長文・空所補充・選択・自由）と、形式ごとのデータ（payload）。
# answer_source は解答の出どころ（material: 教材にあった / ai: AI が作った）。AI の解答は承認されるまで出題しない。
# crop_regions.generate_answers は「構造化を開始」したときの「解答を AI で作る」の選択（初期値 ON）。
class AddQuestionTypesToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :question_type, :string
    add_column :questions, :payload, :jsonb, default: {}, null: false
    add_column :questions, :answer_source, :string, default: "material", null: false
    add_check_constraint :questions, "question_type IS NULL OR question_type IN ('reorder', 'translate_en_ja', 'compose_ja_en', 'passage', 'fill_blank', 'choice', 'free')", name: "questions_question_type_values"
    add_check_constraint :questions, "answer_source IN ('material', 'ai')", name: "questions_answer_source_values"
    add_column :crop_regions, :generate_answers, :boolean, default: true, null: false
  end
end
