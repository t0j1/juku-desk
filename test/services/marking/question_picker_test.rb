require "test_helper"

class Marking::QuestionPickerTest < ActiveSupport::TestCase
  def make_q(approved: true, **attrs)
    region = make_regions(1, status: :extracted).first
    region.create_question!({ subject: "英語", question_text: "問", answer_text: "答", reviewed_at: (Time.current if approved) }.merge(attrs))
  end

  def params(**o)
    Marking::QuestionPicker::Params.new({ mode: "random", count: 10, tags: [], tag_logic: "or" }.merge(o))
  end

  test "only approved questions, no duplicates, and never more than exist" do
    3.times { make_q }
    make_q(approved: false)
    picked = Marking::QuestionPicker.new(params(count: 10)).pick
    assert_equal 3, picked.size
    assert_equal picked.map(&:id).uniq, picked.map(&:id)
  end

  test "subject and difficulty range filter" do
    a = make_q(subject: "数学", difficulty: 2)
    make_q(subject: "数学", difficulty: 5)
    make_q(subject: "英語", difficulty: 2)
    make_q(subject: "数学", difficulty: nil)
    assert_equal [ a.id ], Marking::QuestionPicker.new(params(subject: "数学", difficulty_min: 1, difficulty_max: 3)).pick.map(&:id)
  end

  test "tag AND requires all tags, OR requires any" do
    both = make_q(tags: %w[文法 時制])
    one = make_q(tags: %w[文法])
    make_q(tags: %w[語彙])
    assert_equal [ both.id ], Marking::QuestionPicker.new(params(tags: %w[文法 時制], tag_logic: "and")).pick.map(&:id)
    assert_equal [ both.id, one.id ].sort, Marking::QuestionPicker.new(params(tags: %w[文法 時制], tag_logic: "or")).pick.map(&:id).sort
  end
end
