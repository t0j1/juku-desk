# 出題フォームの入力を検証して、小テスト（tests / test_items）を作る。
module Marking
  class TestBuilder
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :title, :string
    attribute :mode, :string, default: "random"
    attribute :count, :integer, default: 10
    attribute :subject, :string
    attribute :tags_text, :string
    attribute :tag_logic, :string, default: "or"
    attribute :difficulty_min, :integer
    attribute :difficulty_max, :integer
    attribute :group_by_type, :boolean, default: false
    attribute :type_order, :string, default: SectionTemplate::DEFAULT_ORDER.join(",")

    validates :title, presence: true, length: { maximum: 100 }
    validates :mode, inclusion: { in: Exam::MODES }
    validates :count, numericality: { only_integer: true, greater_than: 0 }
    validates :subject, inclusion: { in: Question::SUBJECTS }, allow_blank: true
    validates :tag_logic, inclusion: { in: %w[and or] }
    validates :difficulty_min, :difficulty_max, inclusion: { in: 1..5 }, allow_nil: true
    validate :check_count_limit, :check_tags_for_mode, :check_difficulty_order

    attr_reader :test

    def tags = tags_text.to_s.split(/[,、\s]+/).map(&:strip).reject(&:empty?).uniq

    # 保存した小テスト（または検証エラー）。問題が 0 件のときも作らない（印刷する紙がないため）
    def save(user)
      return false unless valid?

      picked = picker.pick
      if picked.empty?
        errors.add(:base, "条件に合う承認済みの問題がありません")
        return false
      end

      Exam.transaction do
        @test = Exam.create!(title: title, mode: mode, subject: subject.presence, created_by: user, filter: filter_json)
        if group_by_type
          Marking::SectionNumbering.new(picked, type_order_list).entries.each do |e|
            @test.items.create!(question: e.question, position: e.position, section: e.section, sub_position: e.sub_position, question_type: e.question_type)
          end
        else
          picked.each.with_index(1) { |q, pos| @test.items.create!(question: q, position: pos) }
        end
      end
      true
    end

    # 形式の並び（画面で入れ替えたもの。不正な値は捨て、足りない形式は既定の順で補う）
    def type_order_list = Marking::SectionNumbering.normalize_order(type_order)

    private
      def picker
        Marking::QuestionPicker.new(Marking::QuestionPicker::Params.new(
          mode: mode, count: count, subject: subject.presence, tags: tags, tag_logic: tag_logic,
          difficulty_min: difficulty_min, difficulty_max: difficulty_max))
      end

      def filter_json
        { "count" => count, "subject" => subject.presence, "tags" => tags, "tag_logic" => tag_logic,
          "difficulty_min" => difficulty_min, "difficulty_max" => difficulty_max,
          "group_by_type" => group_by_type, "type_order" => (group_by_type ? type_order_list : nil) }
      end

      def check_count_limit
        max = Marking::QuestionPicker.max_count
        errors.add(:count, "は #{max} 問までです") if count && count > max
      end

      def check_tags_for_mode
        errors.add(:tags_text, "を 1 つ以上入れてください（タグ別のとき）") if mode == "by_tag" && tags.empty?
      end

      def check_difficulty_order
        errors.add(:difficulty_max, "は下限以上にしてください") if difficulty_min && difficulty_max && difficulty_max < difficulty_min
      end
  end
end
