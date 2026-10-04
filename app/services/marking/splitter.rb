module Marking
  # 1 つの問題に〔12〕〔13〕… が混ざっているとき（PR #55 より前の構造化で作られたもの）、〔n〕の位置で問題ごとに分ける。
  # 問題文・解答・解説を、同じ〔n〕どうしで組み合わせる。
  # 確実に分けられないとき（番号が 2 つ未満、番号の並びが問題文と解答で違う、解説の番号が合わない）は nil を返す（手で直してもらう）。
  module Splitter
    LABEL = /〔\s*[0-9０-９]+\s*〕/

    Part = Struct.new(:source_label, :question_text, :answer_text, :explanation, keyword_init: true)

    module_function

    def call(question)
      return nil if question.options.present? # 選択肢をどの問題に付けるかは決められない

      questions = segments(with_label(question.question_text, question.source_label))
      answers = segments(with_label(question.answer_text, question.source_label))
      return nil unless questions && answers && questions.size >= 2
      return nil unless questions.map(&:first) == answers.map(&:first)

      explanations = question.explanation.to_s.strip.empty? ? nil : segments(with_label(question.explanation, question.source_label))
      if question.explanation.to_s.strip.present?
        return nil unless explanations && explanations.map(&:first) == questions.map(&:first)
      end

      questions.each_with_index.map do |(label, text), i|
        Part.new(source_label: label, question_text: text, answer_text: answers[i].last, explanation: explanations ? explanations[i].last : "")
      end
    end

    # "〔12〕本文〔13〕本文" → [["〔12〕", "本文"], ["〔13〕", "本文"]]。先頭に番号の無い文がある・番号が重複する・本文が空なら nil
    def segments(text)
      text = text.to_s.strip
      return nil unless text.match?(/\A#{LABEL}/o)

      parts = text.split(/(#{LABEL})/o).reject(&:empty?)
      pairs = parts.each_slice(2).map { |label, body| [ normalize(label), body.to_s.strip ] }
      return nil if pairs.any? { |label, body| !label.match?(LABEL) || body.empty? }
      return nil unless pairs.map(&:first).uniq.size == pairs.size

      pairs
    end

    # 新しい構造化では先頭の番号が source_label に移っているので、本文の先頭に戻してから分ける
    def with_label(text, label)
      text = text.to_s.strip
      return text if label.blank? || !label.match?(LABEL) || text.match?(/\A#{LABEL}/o)

      "#{label}#{text}"
    end

    def normalize(label) = label.gsub(/\s/, "").tr("０-９", "0-9")
  end
end
