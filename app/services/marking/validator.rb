module Marking
  # Gemini の応答（JSON 文字列）をスキーマで検証し、保存する形にそろえる。
  # 応答は { "questions": [ {...}, ... ] }（1 領域に複数の問題）。旧形式の 1 問だけのオブジェクトも受け付ける。
  #   Result#status … :extracted（そのまま使える）/ :needs_review（どれかの問題の科目が null か 5 科目以外）/ :failed
  #   Result#attributes … 問題ごとの属性の配列
  # 英語の問題は question_type（判定できなければ free）と payload を持つ。英語以外は question_type が null。
  # 解答：教材にあればそれ（answer_source=material）、無ければ AI が作ったもの（answer_source=ai）。
  #   generate_answers: false のときは AI の解答を使わず answer_text を空にし、needs_review にする
  module Validator
    Result = Struct.new(:status, :attributes, :error, :raw, keyword_init: true)

    module_function

    def call(raw_text, generate_answers: true)
      data = JSON.parse(raw_text)
      return failed("応答が JSON オブジェクトではありません", raw_text) unless data.is_a?(Hash)

      items = data.key?("questions") ? data["questions"] : [ data ]
      return failed("questions が配列ではありません", data) unless items.is_a?(Array)
      return failed("questions が空です", data) if items.empty?
      return failed("questions の要素が JSON オブジェクトではありません", data) unless items.all?(Hash)

      attributes = []
      items.each_with_index do |item, i|
        attrs, error = question_attributes(item, generate_answers)
        return failed(items.size > 1 ? "#{i + 1} 問目: #{error}" : error, data) if error

        attributes << attrs
      end

      complete = attributes.all? { |a| a[:subject] && a[:answer_text].present? }
      Result.new(status: complete ? :extracted : :needs_review, raw: data, attributes: attributes)
    rescue JSON::ParserError
      failed("応答を JSON として読めません", raw_text)
    end

    def question_attributes(item, generate_answers)
      question = item["question_text"].to_s.strip
      answer = item["answer_text"].to_s.strip
      # answer_in_material が無い（旧形式の応答）ときは教材の解答とみなす
      from_material = item["answer_in_material"] != false
      answer = "" if !generate_answers && !from_material
      return [ nil, "question_text が空です" ] if question.empty?
      return [ nil, "answer_text が空です" ] if answer.empty? && generate_answers

      options = item["options"]
      return [ nil, "options が配列ではありません" ] unless options.nil? || (options.is_a?(Array) && options.all? { |o| o.is_a?(String) })

      tags = Array(item["tags"]).map { |t| t.to_s.strip }.reject(&:empty?).uniq
      tags = [ Question::NEEDS_CONFIRMATION_TAG ] if tags.empty?
      subject = item["subject"]
      valid_subject = Question::SUBJECTS.include?(subject)
      type = question_type(item, valid_subject ? subject : nil)

      [ {
        subject: valid_subject ? subject : nil, source_label: item["source_label"].to_s.strip.presence, question_text: question, options: Array(options).map(&:strip),
        question_type: type, payload: Question.normalize_payload(type, item["payload"]),
        answer_text: answer, answer_source: answer.present? && !from_material ? "ai" : "material", explanation: item["explanation"].to_s.strip, tags: tags, raw_ai: { "response" => item, "model" => GeminiConfig.model }
      }, nil ]
    end

    # 形式は英語だけ。英語で形式が無い・知らない値なら free。科目が不明なら、返ってきた形式を（正しい値なら）残す
    def question_type(item, subject)
      type = item["question_type"]
      valid = Question::TYPES.include?(type)
      return valid ? type : "free" if subject == "英語"
      return nil if subject

      valid ? type : nil
    end

    def failed(message, raw)
      Result.new(status: :failed, error: message, raw: raw)
    end
  end
end
