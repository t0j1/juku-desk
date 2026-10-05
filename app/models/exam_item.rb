class ExamItem < ApplicationRecord
  self.table_name = "test_items"

  belongs_to :test, class_name: "Exam", inverse_of: :items
  belongs_to :question

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :section, :sub_position, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # 印刷の番号：形式ごとのときは (小問)、そうでなければ通し番号
  def number_label = section ? "(#{sub_position})" : position.to_s
end
