module PdfSplitter
  # 「回ごとの問題＋解答」の入力を境界の行に展開する。問題をすべて並べてから解答を並べる
  module PairRows
    def self.expand(pairs)
      rows = Array(pairs).map { |p| (p.respond_to?(:to_unsafe_h) ? p.to_unsafe_h : p.to_h).stringify_keys }
      rows = rows.reject { |p| %w[problem_from problem_to answer_from answer_to].all? { |k| p[k].blank? } }
      problems = rows.map { |p| { "from" => p["problem_from"], "to" => p["problem_to"], "round" => p["round"], "kind" => "problem", "label" => "#{p['round'].presence || '回名なし'}の問題" } }
      answers  = rows.map { |p| { "from" => p["answer_from"],  "to" => p["answer_to"],  "round" => p["round"], "kind" => "answer", "label" => "#{p['round'].presence || '回名なし'}の解答" } }
      problems + answers
    end

    # 保存済みの境界から、回ごとのペアを作り直す（画面の初期値）
    def self.from_boundaries(boundaries)
      bs = Array(boundaries)
      ps = bs.select { |b| b["kind"] == "problem" }
      as = bs.select { |b| b["kind"] == "answer" }
      Array.new([ ps.size, as.size ].max) do |i|
        p, a = ps[i] || {}, as[i] || {}
        { "round" => p["round"] || a["round"], "problem_from" => p["from"], "problem_to" => p["to"],
          "answer_from" => a["from"], "answer_to" => a["to"] }
      end
    end
  end
end
