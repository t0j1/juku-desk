# 小テストの出題条件に合う問題を選ぶ。出題対象の SQL はここ 1 か所だけ（承認済みのみ・重複なし）。
# 足りないときは「ある分だけ」を返す。別の条件の問題では補わない。
module Marking
  class QuestionPicker
    Params = Struct.new(:mode, :count, :subject, :tags, :tag_logic, :difficulty_min, :difficulty_max, keyword_init: true)

    def self.max_count = ENV.fetch("MARKING_TEST_MAX_COUNT", 50).to_i

    def initialize(params)
      @params = params
    end

    # 条件に合う承認済みの問題（並びは未指定）
    def scope
      s = Question.approved
      s = s.where(subject: @params.subject) if @params.subject.present?
      s = s.where("questions.difficulty >= ?", @params.difficulty_min) if @params.difficulty_min
      s = s.where("questions.difficulty <= ?", @params.difficulty_max) if @params.difficulty_max
      tags = Array(@params.tags)
      if tags.any?
        op = @params.tag_logic == "and" ? "@>" : "&&"
        s = s.where("questions.tags #{op} ARRAY[?]::text[]", tags)
      end
      s
    end

    def available_count = scope.count

    def pick
      scope.order(Arel.sql("RANDOM()")).limit(@params.count).to_a
    end
  end
end
