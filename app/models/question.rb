# Gemini が赤枠の領域から作った問題。subject が null（または 5 科目以外だったもの）は「要確認」。
class Question < ApplicationRecord
  SUBJECTS = %w[英語 数学 国語 理科 社会].freeze
  NEEDS_CONFIRMATION_TAG = "要確認".freeze

  belongs_to :region, class_name: "CropRegion", inverse_of: :questions
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :subject, inclusion: { in: SUBJECTS }, allow_nil: true
  validates :difficulty, inclusion: { in: 1..5 }, allow_nil: true

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

  # 承認できるのは、科目が決まっていて、問題文と解答が入っているものだけ
  def approvable? = subject.present? && question_text.present? && answer_text.present?

  def approve!(user)
    raise ActiveRecord::RecordInvalid, self unless approvable?

    update!(reviewed_at: Time.current, reviewed_by: user)
  end

  def unapprove!
    update!(reviewed_at: nil, reviewed_by: nil)
  end
end
