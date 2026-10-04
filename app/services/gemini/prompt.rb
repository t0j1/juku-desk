module Gemini
  module Prompt
    TEXT = <<~PROMPT.freeze
      これは学習塾の教材の一部を赤枠で切り出した画像です。中に〔1〕〔2〕のように複数の問題があれば、1 問ずつ分けて questions の配列にしてください。1 問だけなら要素 1 つの配列です。
      各要素は次の JSON です。
      - subject: 英語・数学・国語・理科・社会のどれか。判断できなければ null
      - source_label: 問題番号（〔1〕・(2)・問3 など）。無ければ null。question_text には含めない
      - question_text: 問題文（選択肢と問題番号は含めない）
      - options: 選択肢の配列。記述式なら空配列
      - answer_text: 解答（画像に無ければ、正しい解答を推定して書く）
      - explanation: 解説。無ければ空文字
      - tags: 単元や分野のタグ（1 件以上）。読み取れなければ ["要確認"]
      - confidence: 読み取りと構造化への自信（0〜1）
      画像に書かれていない内容を作り足さないでください。
    PROMPT
  end
end
