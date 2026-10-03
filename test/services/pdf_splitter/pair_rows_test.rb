require "test_helper"

class PdfSplitter::PairRowsTest < ActiveSupport::TestCase
  test "expands pairs into all problems then all answers, skipping blank rows" do
    rows = PdfSplitter::PairRows.expand([
      { round: "第1回", problem_from: 2, problem_to: 20, answer_from: 153, answer_to: 164 },
      { round: "第2回", problem_from: 21, problem_to: 39, answer_from: 165, answer_to: 177 },
      { round: "第3回" }
    ])
    assert_equal [ [ 2, 20, "problem" ], [ 21, 39, "problem" ], [ 153, 164, "answer" ], [ 165, 177, "answer" ] ],
                 rows.map { |r| [ r["from"], r["to"], r["kind"] ] }
  end

  test "rebuilds pairs from saved boundaries" do
    pairs = PdfSplitter::PairRows.from_boundaries([
      { "from" => 2, "to" => 20, "round" => "第1回", "kind" => "problem" },
      { "from" => 153, "to" => 164, "round" => "第1回", "kind" => "answer" }
    ])
    assert_equal [ { "round" => "第1回", "problem_from" => 2, "problem_to" => 20, "answer_from" => 153, "answer_to" => 164 } ], pairs
  end
end
