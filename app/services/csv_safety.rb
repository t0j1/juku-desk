# CSV を Excel などで開いたとき、セルが数式として実行されないようにする（先頭が = + - @ タブ 改行 のものに ' を付ける）
module CsvSafety
  module_function

  def cell(value)
    text = value.to_s
    text.match?(/\A[=+\-@\t\r]/) ? "'#{text}" : text
  end
end
