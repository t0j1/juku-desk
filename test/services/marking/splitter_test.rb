require "test_helper"

class Marking::SplitterTest < ActiveSupport::TestCase
  def q(**attrs) = Question.new({ options: [], tags: [] }.merge(attrs))

  test "splits question, answer and explanation at the same 〔n〕 labels" do
    parts = Marking::Splitter.call(q(question_text: "〔12〕読みを書け。「憂鬱」〔13〕読みを書け。「薔薇」", answer_text: "〔12〕ゆううつ 〔13〕ばら", explanation: "〔12〕頻出 〔13〕難読"))
    assert_equal [ "〔12〕", "〔13〕" ], parts.map(&:source_label)
    assert_equal [ "読みを書け。「憂鬱」", "読みを書け。「薔薇」" ], parts.map(&:question_text)
    assert_equal %w[ゆううつ ばら], parts.map(&:answer_text)
    assert_equal %w[頻出 難読], parts.map(&:explanation)
  end

  test "the first label moved to source_label by the new structuring is put back; full-width digits match; empty explanation is fine" do
    parts = Marking::Splitter.call(q(source_label: "〔1〕", question_text: "A〔２〕B", answer_text: "a〔2〕b", explanation: ""))
    assert_equal [ "〔1〕", "〔2〕" ], parts.map(&:source_label)
    assert_equal [ "", "" ], parts.map(&:explanation)
  end

  test "returns nil when it cannot be split for sure" do
    assert_nil Marking::Splitter.call(q(question_text: "〔12〕A", answer_text: "〔12〕a"))                      # 1 問だけ
    assert_nil Marking::Splitter.call(q(question_text: "〔12〕A〔13〕B", answer_text: "ア"))                    # 解答に番号が無い
    assert_nil Marking::Splitter.call(q(question_text: "〔12〕A〔13〕B", answer_text: "〔12〕a〔14〕b"))       # 番号が合わない
    assert_nil Marking::Splitter.call(q(question_text: "〔12〕A〔13〕B", answer_text: "〔12〕a〔13〕b", explanation: "まとめて解説")) # 解説が分けられない
    assert_nil Marking::Splitter.call(q(question_text: "〔12〕A〔13〕B", answer_text: "〔12〕a〔13〕b", options: %w[ア イ])) # 選択肢の振り分けが決められない
  end
end
