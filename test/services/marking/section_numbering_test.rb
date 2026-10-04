require "test_helper"

class Marking::SectionNumberingTest < ActiveSupport::TestCase
  Q = Struct.new(:id, :question_type)

  test "groups by type in the given order and restarts sub numbers in each section" do
    qs = [ Q.new(1, "translate_en_ja"), Q.new(2, "reorder"), Q.new(3, nil), Q.new(4, "reorder"), Q.new(5, "translate_en_ja"), Q.new(6, "unknown") ]
    e = Marking::SectionNumbering.new(qs, SectionTemplate::DEFAULT_ORDER).entries
    assert_equal [ 2, 4, 1, 5, 3, 6 ], e.map { |x| x.question.id }
    assert_equal [ 1, 1, 2, 2, 3, 3 ], e.map(&:section)
    assert_equal [ 1, 2, 1, 2, 1, 2 ], e.map(&:sub_position)
    assert_equal (1..6).to_a, e.map(&:position)
    assert_equal %w[reorder reorder translate_en_ja translate_en_ja free free], e.map(&:question_type)
  end

  test "a custom order is honoured; unknown and duplicate types are dropped; missing ones appended" do
    assert_equal %w[translate_en_ja reorder passage compose_ja_en fill_blank choice free],
                 Marking::SectionNumbering.normalize_order("translate_en_ja,bogus,reorder,translate_en_ja")
    qs = [ Q.new(1, "reorder"), Q.new(2, "translate_en_ja") ]
    e = Marking::SectionNumbering.new(qs, "translate_en_ja,reorder").entries
    assert_equal [ 2, 1 ], e.map { |x| x.question.id }
    assert_equal [ 1, 2 ], e.map(&:section)
  end
end
