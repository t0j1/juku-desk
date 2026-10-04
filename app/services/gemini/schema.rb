module Gemini
  # response_schema（Gemini の OpenAPI 風スキーマ）。このキーだけを返させる
  # 1 つの赤枠に〔1〕〔2〕のように複数の問題があるので、questions の配列で返させる
  module Schema
    QUESTION = {
      type: "OBJECT",
      properties: {
        subject: { type: "STRING", nullable: true, enum: Question::SUBJECTS },
        source_label: { type: "STRING", nullable: true },
        question_text: { type: "STRING" },
        options: { type: "ARRAY", items: { type: "STRING" } },
        answer_text: { type: "STRING" },
        explanation: { type: "STRING" },
        tags: { type: "ARRAY", items: { type: "STRING" } },
        confidence: { type: "NUMBER" }
      },
      required: %w[subject question_text options answer_text explanation tags confidence]
    }.freeze

    RESPONSE = {
      type: "OBJECT",
      properties: { questions: { type: "ARRAY", items: QUESTION } },
      required: %w[questions]
    }.freeze
  end
end
