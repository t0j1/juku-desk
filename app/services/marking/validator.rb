module Marking
  # Gemini の応答（JSON 文字列）をスキーマで検証し、保存する形にそろえる。
  #   Result#status … :extracted（そのまま使える）/ :needs_review（科目が null か 5 科目以外）/ :failed
  module Validator
    Result = Struct.new(:status, :attributes, :error, :raw, keyword_init: true)

    module_function

    def call(raw_text)
      data = JSON.parse(raw_text)
      return failed("応答が JSON オブジェクトではありません", raw_text) unless data.is_a?(Hash)

      question = data["question_text"].to_s.strip
      answer = data["answer_text"].to_s.strip
      return failed("question_text が空です", data) if question.empty?
      return failed("answer_text が空です", data) if answer.empty?

      options = data["options"]
      return failed("options が配列ではありません", data) unless options.nil? || (options.is_a?(Array) && options.all? { |o| o.is_a?(String) })

      tags = Array(data["tags"]).map { |t| t.to_s.strip }.reject(&:empty?).uniq
      tags = [ Question::NEEDS_CONFIRMATION_TAG ] if tags.empty?
      subject = data["subject"]
      valid_subject = Question::SUBJECTS.include?(subject)

      Result.new(
        status: valid_subject ? :extracted : :needs_review,
        raw: data,
        attributes: {
          subject: valid_subject ? subject : nil, question_text: question, options: Array(options).map(&:strip),
          answer_text: answer, explanation: data["explanation"].to_s.strip, tags: tags, raw_ai: { "response" => data, "model" => GeminiConfig.model }
        }
      )
    rescue JSON::ParserError
      failed("応答を JSON として読めません", raw_text)
    end

    def failed(message, raw)
      Result.new(status: :failed, error: message, raw: raw)
    end
  end
end
