class ExamItem < ApplicationRecord
  self.table_name = "test_items"

  belongs_to :test, class_name: "Exam", inverse_of: :items
  belongs_to :question

  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
