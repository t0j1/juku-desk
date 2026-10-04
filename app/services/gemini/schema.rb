module Gemini
  # response_schema（Gemini の OpenAPI 風スキーマ）。このキーだけを返させる
  module Schema
    QUESTION = {
      type: "OBJECT",
      properties: {
        subject: { type: "STRING", nullable: true, enum: Question::SUBJECTS },
        question_text: { type: "STRING" },
        options: { type: "ARRAY", items: { type: "STRING" } },
        answer_text: { type: "STRING" },
        explanation: { type: "STRING" },
        tags: { type: "ARRAY", items: { type: "STRING" } },
        confidence: { type: "NUMBER" }
      },
      required: %w[subject question_text options answer_text explanation tags confidence]
    }.freeze
  end
end
