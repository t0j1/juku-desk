require "test_helper"

class Marking::LatexTextTest < ActiveSupport::TestCase
  def inline(text) = Marking::LatexText.inline(text)

  test "square roots, fractions and pi" do
    assert_equal "-√3", inline('$-\sqrt{3}$')
    assert_equal "√3/2", inline('$\frac{\sqrt{3}}{2}$')
    assert_equal "7/6π", inline('$\frac{7}{6}\pi$')
    assert_equal "(x+1)/(x-1)", inline('$\frac{x+1}{x-1}$')
    assert_equal "√(x+1)", inline('$\sqrt{x+1}$')
  end

  test "powers and subscripts become sup and sub" do
    assert_equal "cos<sup>2</sup>x", inline('$\cos^2 x$')
    assert_equal "x<sup>2</sup>+y<sub>1</sub>", inline('$x^2+y_1$')
    assert_equal "a<sup>n+1</sup>", inline('$a^{n+1}$')
    assert_equal "<sup>3</sup>√8", inline('$\sqrt[3]{8}$')
  end

  test "operators and symbols" do
    assert_equal "a≤b", inline('$a \le b$')
    assert_equal "30°", inline('$30^\circ$').sub("<sup>°</sup>", "°")
    assert_equal "2×3", inline('$2 \times 3$')
  end

  test "text outside the dollars is escaped and kept, display math is handled" do
    assert_equal "a &lt; b のとき √2", inline('a < b のとき $\sqrt{2}$')
    assert_equal "x=1", inline("$$\nx = 1\n$$")
    assert_equal "5 &amp; 6", inline("5 & 6")
  end

  test "no raw LaTeX source is left in the output" do
    out = inline('$\frac{\sqrt{3}}{2}$ と $\cos^2 x$ と $\left(\frac{1}{2}\right)$')
    assert_no_match(/\\|\{|\}|\^|frac|sqrt/, out)
  end

  test "an unknown command is refused instead of printed raw" do
    assert_raises(Marking::LatexText::Unsupported) { inline('$\begin{cases} x \end{cases}$') }
    assert_raises(Marking::LatexText::Unsupported) { inline('$\frac{1}$') }
    assert_raises(Marking::LatexText::Unsupported) { inline('$a}$') }
  end
end
