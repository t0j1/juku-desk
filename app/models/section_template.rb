# 大問の指示文（問題形式ごと）。行が無ければ DEFAULTS を使う。system_admin と staff が編集できる。
class SectionTemplate < ApplicationRecord
  DEFAULTS = {
    "reorder" => "次の（ ）内の語を並べ替えて，英文を完成させなさい。",
    "passage" => "次の文章を読んで，後の問いに答えなさい。",
    "translate_en_ja" => "次の文を訳しなさい。",
    "compose_ja_en" => "日本語に合うように，英文を書きなさい。",
    "fill_blank" => "次の（ ）に入る適切な語を書きなさい。",
    "choice" => "次の問いの答えを選びなさい。",
    "free" => "次の問いに答えなさい。"
  }.freeze
  # 「形式ごとに並べる」の初期の順番
  DEFAULT_ORDER = %w[reorder passage translate_en_ja compose_ja_en fill_blank choice free].freeze

  belongs_to :updated_by, class_name: "User", optional: true

  validates :question_type, inclusion: { in: Question::TYPES }, uniqueness: true
  validates :instruction, presence: true, length: { maximum: 300 }

  def self.for(type)
    find_by(question_type: type) || new(question_type: type, instruction: DEFAULTS.fetch(type))
  end

  def self.all_for_types = DEFAULT_ORDER.map { |t| self.for(t) }

  # { "reorder" => "次の…", ... }（印刷で 1 回だけ引く）
  def self.instructions
    saved = all.pluck(:question_type, :instruction).to_h
    DEFAULTS.merge(saved)
  end

  def self.reset!(type) = where(question_type: type).destroy_all

  def label = Question::TYPE_LABELS[question_type]
  def customized? = persisted?
end
