# 選んだ問題を形式の順に並べ、大問【1】【2】…と小問(1)(2)…の番号を振る。
# 形式が無い問題（英語以外など）は free として扱う。同じ形式の中では、選ばれた順を保つ。
module Marking
  class SectionNumbering
    Entry = Struct.new(:question, :question_type, :section, :sub_position, :position, keyword_init: true)

    # order: 形式の並び。足りない形式は既定の順で後ろに足し、知らない形式は捨てる
    def self.normalize_order(order)
      list = (order.is_a?(String) ? order.split(",") : Array(order)).map { |t| t.to_s.strip }
      list = list.select { |t| Question::TYPES.include?(t) }.uniq
      list + (SectionTemplate::DEFAULT_ORDER - list)
    end

    def initialize(questions, order)
      @questions = questions
      @order = self.class.normalize_order(order)
    end

    def entries
      groups = @questions.group_by { |q| type_of(q) }
      position = 0
      @order.select { |t| groups.key?(t) }.each.with_index(1).flat_map do |type, section|
        groups[type].each.with_index(1).map do |q, sub|
          Entry.new(question: q, question_type: type, section: section, sub_position: sub, position: position += 1)
        end
      end
    end

    private
      def type_of(q) = Question::TYPES.include?(q.question_type) ? q.question_type : "free"
  end
end
