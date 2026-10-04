module Gemini
  # response_schema（Gemini の OpenAPI 風スキーマ）。このキーだけを返させる
  # 1 つの赤枠に〔1〕〔2〕のように複数の問題があるので、questions の配列で返させる
  # question_type と payload は英語のときだけ使う（形式ごとの payload のキーは Question::PAYLOAD_KEYS）
  module Schema
    PAYLOAD = {
      type: "OBJECT",
      nullable: true,
      properties: {
        ja: { type: "STRING" },
        words: { type: "ARRAY", items: { type: "STRING" } },
        prefix: { type: "STRING" },
        suffix: { type: "STRING" },
        extra_count: { type: "INTEGER" },
        source: { type: "STRING" },
        template: { type: "STRING" },
        blank_count: { type: "INTEGER" },
        body: { type: "STRING" },
        sub_questions: {
          type: "ARRAY",
          items: { type: "OBJECT", properties: { prompt: { type: "STRING" }, answer: { type: "STRING" } }, required: %w[prompt answer] }
        }
      }
    }.freeze

    QUESTION = {
      type: "OBJECT",
      properties: {
        subject: { type: "STRING", nullable: true, enum: Question::SUBJECTS },
        source_label: { type: "STRING", nullable: true },
        question_type: { type: "STRING", nullable: true, enum: Question::TYPES },
        payload: PAYLOAD,
        question_text: { type: "STRING", description: "数式は $...$ か $$...$$ で囲んだ LaTeX。日本語の文章は LaTeX にしない" },
        options: { type: "ARRAY", items: { type: "STRING", description: "数式は $...$ か $$...$$ で囲んだ LaTeX。日本語の文章は LaTeX にしない" } },
        answer_text: { type: "STRING", description: "数式は $...$ か $$...$$ で囲んだ LaTeX。日本語の文章は LaTeX にしない" },
        answer_in_material: { type: "BOOLEAN" },
        explanation: { type: "STRING", description: "数式は $...$ か $$...$$ で囲んだ LaTeX。日本語の文章は LaTeX にしない" },
        tags: { type: "ARRAY", items: { type: "STRING" } },
        confidence: { type: "NUMBER" }
      },
      required: %w[subject question_text options answer_text answer_in_material explanation tags confidence]
    }.freeze

    RESPONSE = {
      type: "OBJECT",
      properties: { questions: { type: "ARRAY", items: QUESTION } },
      required: %w[questions]
    }.freeze
  end
end
