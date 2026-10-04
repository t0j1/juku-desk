# 承認済みの問題から作った小テスト（テーブルは tests）。Test という名前はテストライブラリと紛らわしいので Exam としている。
class Exam < ApplicationRecord
  self.table_name = "tests"

  MODES = %w[random by_tag].freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :items, -> { order(:position) }, class_name: "ExamItem", foreign_key: :test_id, inverse_of: :test, dependent: :destroy
  has_many :questions, through: :items

  validates :title, presence: true, length: { maximum: 100 }
  validates :mode, inclusion: { in: MODES }

  def requested_count = filter["count"].to_i
  def shortfall = [ requested_count - items.size, 0 ].max
  def short? = shortfall.positive?
  # 形式ごとに並べて、大問・小問の番号を振った小テストか
  def sectioned? = filter["group_by_type"] == true

  # 大問の指示文 { 形式 => 指示文 }。作成時に保存したものを優先し、保存が無い（以前の）小テストはテンプレートの指示文を使う
  def section_instructions
    saved = Array(sections).to_h { |s| [ s["question_type"], s["instruction"] ] }
    saved.empty? ? SectionTemplate.instructions : SectionTemplate::DEFAULTS.merge(saved)
  end
end
