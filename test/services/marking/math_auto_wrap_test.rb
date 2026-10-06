require "test_helper"

class Marking::MathAutoWrapTest < ActiveSupport::TestCase
  def wrap(s) = Marking::MathAutoWrap.call(s)

  test "wraps bare powers, fractions and functions" do
    assert_equal "$\\cos^2 x$", wrap("cos^2 x")
    assert_equal "$\\frac{7}{6π}$", wrap("7/6π")
    assert_equal "$\\frac{π}{2}$", wrap("π/2")
    assert_equal "$\\frac{1}{2} \\sin 2x = \\frac{1}{4}$", wrap("(1/2) sin 2x = 1/4")
    assert_equal "答えは $x = \\frac{π}{2}$ です", wrap("答えは x = π/2 です")
  end

  test "wraps sqrt" do
    assert_equal "$x = \\sqrt{3}$", wrap("x = √3")
    assert_equal "答え $\\sqrt{2x}$", wrap("答え sqrt(2x)")
  end

  test "wrapping is idempotent" do
    once = wrap("cos^2 x と 7/6π")
    assert_equal once, wrap(once)
  end

  test "leaves already wrapped math, plain prose and dollar text alone" do
    [ "$\\cos^2 x$ です", "$$\\frac{1}{2}$$", "Tom and Jerry", "2024/10/6 に実施", "速さは 5 km/h", "価格は $5 と $10 です", "" ].each { |s| assert_equal s, wrap(s) }
  end

  test "wraps only the bare part next to wrapped math" do
    assert_equal "$a^2$ と $\\sin^2 x$", wrap("$a^2$ と sin^2 x")
  end

  test "LatexText renders the wrapped result as sup and fractions" do
    assert_equal "cos<sup>2</sup>x", Marking::LatexText.inline(wrap("cos^2 x"))
    assert_equal "7/6π", Marking::LatexText.inline(wrap("7/6π"))
  end

  test "Question#math_text only applies to math and science" do
    assert_equal "$\\frac{π}{2}$", Question.new(subject: "数学").math_text("π/2")
    assert_equal "π/2", Question.new(subject: "英語").math_text("π/2")
  end
end
