module Gemini
  module Prompt
    BASE = <<~PROMPT.freeze
      これは学習塾の教材の一部を赤枠で切り出した画像です。中に〔1〕〔2〕のように複数の問題があれば、1 問ずつ分けて questions の配列にしてください。1 問だけなら要素 1 つの配列です。
      各要素は次の JSON です。
      - subject: 英語・数学・国語・理科・社会のどれか。判断できなければ null
      - source_label: 問題番号（〔1〕・(2)・問3 など）。無ければ null。question_text には含めない
      - question_type: 英語のときだけ、問題の形式を次から選ぶ。どれにも当てはまらなければ free。英語以外は null
        reorder（語の並べ替え）/ translate_en_ja（英文を和訳）/ compose_ja_en（日本語に合う英文を書く）/ passage（長文読解）/ fill_blank（空所補充）/ choice（選択）/ free
      - payload: 形式ごとのデータ。英語以外・choice・free は null
        reorder: ja（日本語の文）, words（（ ）内の語の配列。順番は画像のまま）, prefix（（ ）の前の英文）, suffix（（ ）の後ろの英文）, extra_count（〔1語不要〕などの不要な語の数。無ければ 0）
        translate_en_ja: source（訳す英文）
        compose_ja_en: ja（日本語の文）, template（空所を ___ で表した英文）, blank_count（空所の数）
        passage: body（本文。下線は <u>…</u>、記号は (ア) のように書く）, sub_questions（小問の配列。それぞれ prompt と answer）
        fill_blank: body（本文。空所は ___）, blank_count（空所の数）
      - question_text: 問題文（選択肢と問題番号は含めない）
      - options: 選択肢の配列。記述式なら空配列
    PROMPT

    WITH_ANSWERS = <<~PROMPT.freeze
      - answer_text: 解答。画像に無ければ、正しい解答を作って書く
      - answer_in_material: 解答が画像に書かれていれば true、自分で作ったなら false
    PROMPT

    WITHOUT_ANSWERS = <<~PROMPT.freeze
      - answer_text: 画像に書かれている解答。画像に無ければ空文字（自分で作らない）
      - answer_in_material: 解答が画像に書かれていれば true、無ければ false
    PROMPT

    TAIL = <<~PROMPT.freeze
      - explanation: 解説。無ければ空文字
      - tags: 単元や分野のタグ（1 件以上）。読み取れなければ ["要確認"]
      - confidence: 読み取りと構造化への自信（0〜1）
      数式は、question_text・options・answer_text・explanation のすべてで、LaTeX を $...$（文章の中）か $$...$$（独立した行）で囲んで書いてください（例：$\\sin x = -\\frac{1}{2}$、$\\sqrt{3}/2$ は $\\frac{\\sqrt{3}}{2}$）。日本語の文章は LaTeX にせず、数式の部分だけを囲みます。数式でない $ は使わないでください。
      画像に書かれていない問題の内容を作り足さないでください。
    PROMPT

    # 赤枠が無く、ページ全体を送るときだけ先頭に足す
    WHOLE_PAGE = <<~PROMPT.freeze
      【重要】この画像は赤枠で切り出したものではなく、教材のページ全体です。ページの中の問題だけを、上から順に 1 問ずつ questions の配列にしてください。
      章見出し・節見出し・ページ番号・柱（ページの上下の見出し）・解説文・コラム・図の説明文は、問題にしないでください。問題が 1 つも無ければ空の配列にしてください。

    PROMPT

    TEXT = (BASE + WITH_ANSWERS + TAIL).freeze
    TEXT_WITHOUT_ANSWERS = (BASE + WITHOUT_ANSWERS + TAIL).freeze

    def self.for(generate_answers:, whole: false)
      text = generate_answers ? TEXT : TEXT_WITHOUT_ANSWERS
      whole ? WHOLE_PAGE + text : text
    end
  end
end
