require "test_helper"

class PrintLayoutHelperTest < ActionView::TestCase
  test "passage body escapes HTML but keeps underline and marks" do
    html = print_passage_body("A (ア) <u>b</u> <script>x</script>")
    assert_includes html, %(<span class="mt-mark">(ア)</span>)
    assert_includes html, %(<u class="mt-underline">b</u>)
    assert_includes html, "&lt;script&gt;"
  end

  test "blanks become equal-width boxes and other HTML is escaped" do
    html = print_blanks("I ___ <b>at</b> _____ six.")
    assert_equal 2, html.scan("mt-blank-gap").size
    assert_includes html, "&lt;b&gt;"
  end

  test "layout falls back when the payload is missing" do
    assert_nil print_layout_for(Question.new(question_type: "reorder", payload: {}))
    assert_equal "reorder", print_layout_for(Question.new(question_type: "reorder", payload: { "words" => %w[a] }))
    assert_nil print_layout_for(Question.new(question_type: "choice", payload: {}))
  end
end
