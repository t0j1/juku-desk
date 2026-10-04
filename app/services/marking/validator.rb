module Marking
  # Gemini の応答（JSON 文字列）をスキーマで検証し、保存する形にそろえる。
  # 応答は { "questions": [ {...}, ... ] }（1 領域に複数の問題）。旧形式の 1 問だけのオブジェクトも受け付ける。
  #   Result#status … :extracted（そのまま使える）/ :needs_review（どれかの問題の科目が null か 5 科目以外）/ :failed
  #   Result#attributes … 問題ごとの属性の配列
  module Validator
    Result = Struct.new(:status, :attributes, :error, :raw, keyword_init: true)

    module_function

    def call(raw_text)
      data = JSON.parse(raw_text)
      return failed("応答が JSON オブジェクトではありません", raw_text) unless data.is_a?(Hash)

      items = data.key?("questions") ? data["questions"] : [ data ]
      return failed("questions が配列ではありません", data) unless items.is_a?(Array)
      return failed("questions が空です", data) if items.empty?
      return failed("questions の要素が JSON オブジェクトではありません", data) unless items.all?(Hash)

      attributes = []
      items.each_with_index do |item, i|
        attrs, error = question_attributes(item, data)
        return failed(items.size > 1 ? "#{i + 1} 問目: #{error}" : error, data) if error

        attributes << attrs
      end

      Result.new(status: attributes.all? { |a| a[:subject] } ? :extracted : :needs_review, raw: data, attributes: attributes)
    rescue JSON::ParserError
      failed("応答を JSON として読めません", raw_text)
    end

    def question_attributes(item, data)
      question = item["question_text"].to_s.strip
      answer = item["answer_text"].to_s.strip
      return [ nil, "question_text が空です" ] if question.empty?
      return [ nil, "answer_text が空です" ] if answer.empty?

      options = item["options"]
      return [ nil, "options が配列ではありません" ] unless options.nil? || (options.is_a?(Array) && options.all? { |o| o.is_a?(String) })

      tags = Array(item["tags"]).map { |t| t.to_s.strip }.reject(&:empty?).uniq
      tags = [ Question::NEEDS_CONFIRMATION_TAG ] if tags.empty?
      subject = item["subject"]
      valid_subject = Question::SUBJECTS.include?(subject)

      [ {
        subject: valid_subject ? subject : nil, source_label: item["source_label"].to_s.strip.presence, question_text: question, options: Array(options).map(&:strip),
        answer_text: answer, explanation: item["explanation"].to_s.strip, tags: tags, raw_ai: { "response" => item, "model" => GeminiConfig.model }
      }, nil ]
    end

    def failed(message, raw)
      Result.new(status: :failed, error: message, raw: raw)
    end
  end
end
