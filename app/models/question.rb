# Gemini が赤枠の領域から作った問題。subject が null（または 5 科目以外だったもの）は「要確認」。
class Question < ApplicationRecord
  SUBJECTS = %w[英語 数学 国語 理科 社会].freeze
  MATH_SUBJECTS = %w[数学 理科].freeze

  # 数学・理科は、$ で囲まれていない数式を囲んでから描く（古いデータや AI の囲み忘れ向け）
  def math_text(text) = MATH_SUBJECTS.include?(subject) ? Marking::MathAutoWrap.call(text) : text.to_s
  NEEDS_CONFIRMATION_TAG = "要確認".freeze
  # 問題形式（今は英語だけ判定する。英語以外は null）と、形式ごとの payload のキー
  TYPES = %w[reorder translate_en_ja compose_ja_en passage fill_blank choice free].freeze
  TYPE_LABELS = { "reorder" => "並べ替え", "translate_en_ja" => "和訳", "compose_ja_en" => "英作文", "passage" => "長文読解",
                  "fill_blank" => "空所補充", "choice" => "選択", "free" => "その他" }.freeze
  PAYLOAD_KEYS = {
    "reorder" => %w[ja words prefix suffix extra_count],
    "translate_en_ja" => %w[source],
    "compose_ja_en" => %w[ja template blank_count],
    "passage" => %w[body sub_questions],
    "fill_blank" => %w[body blank_count]
  }.freeze
  ANSWER_SOURCES = %w[material ai].freeze

  belongs_to :region, class_name: "CropRegion", inverse_of: :questions
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :subject, inclusion: { in: SUBJECTS }, allow_nil: true
  validates :difficulty, inclusion: { in: 1..5 }, allow_nil: true
  validates :question_type, inclusion: { in: TYPES }, allow_nil: true
  validates :answer_source, inclusion: { in: ANSWER_SOURCES }
  validate :payload_is_object

  # レビューの対象（問題として読めたもの。スキーマ違反で failed になった領域は除く）
  scope :reviewable, -> { joins(:region).where(crop_regions: { status: %w[extracted needs_review] }) }
  scope :approved, -> { where.not(reviewed_at: nil) }
  scope :unreviewed, -> { where(reviewed_at: nil) }
  # 要確認（科目が未確定）を先頭に、そのあとは新しい順
  scope :review_order, -> { order(Arel.sql("subject IS NOT NULL"), id: :desc) }

  def options_text = options.join("\n")
  def tags_text = tags.join(" ")
  def approved? = reviewed_at.present?
  def needs_confirmation? = subject.blank?
  def ai_answer? = answer_source == "ai"
  def type_label = TYPE_LABELS[question_type]
  def payload_text = payload.present? ? JSON.pretty_generate(payload) : ""

  # 形式に決まったキーだけを残す（文字列・数値・配列の形もそろえる）。形式が無い・free/choice のときは空
  def self.normalize_payload(type, payload)
    return {} unless payload.is_a?(Hash)

    keys = PAYLOAD_KEYS.fetch(type, [])
    payload.to_h.stringify_keys.slice(*keys).filter_map do |key, value|
      value = case key
      when "words" then Array(value).map { |w| w.to_s.strip }.reject(&:empty?)
      when "sub_questions" then Array(value).select { |q| q.is_a?(Hash) }.map { |q| { "prompt" => q["prompt"].to_s.strip, "answer" => q["answer"].to_s.strip } }
      when "extra_count", "blank_count" then value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
      else value.nil? ? nil : value.to_s.strip
      end
      [ key, value ] unless value.nil? || value == "" || value == []
    end.to_h
  end

  # 承認できるのは、科目が決まっていて、問題文と解答が入っているものだけ
  # 小テストで使われている（印刷済みの内容が変わるので、分割はしない）
  def used_in_exam? = ExamItem.exists?(question_id: id)
  def approvable? = subject.present? && question_text.present? && answer_text.present?

  def approve!(user)
    raise ActiveRecord::RecordInvalid, self unless approvable?

    update!(reviewed_at: Time.current, reviewed_by: user)
  end

  def unapprove!
    update!(reviewed_at: nil, reviewed_by: nil)
  end

  private
    def payload_is_object
      errors.add(:payload, "は JSON オブジェクトにしてください") unless payload.is_a?(Hash)
    end
end
