# ログインの試行記録（成功・失敗とも）。管理画面で検索・CSV 出力する。
class LoginEvent < ApplicationRecord
  REASONS = %w[invalid_credentials locked inactive].freeze

  belongs_to :user, optional: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record!(email_address:, user:, success:, reason: nil, request:)
    create!(
      email_address: email_address.to_s.strip.downcase.first(255),
      user: user,
      success: success,
      reason: reason,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(255)
    )
  end

  # q: メールアドレス・IP の部分一致 / result: "success" | "failure" / from, to: 日付（JST）
  def self.search(q: nil, result: nil, from: nil, to: nil)
    scope = all
    if q.present?
      like = "%#{sanitize_sql_like(q.strip)}%"
      scope = scope.where("email_address ILIKE :q OR ip_address ILIKE :q", q: like)
    end
    scope = scope.where(success: result == "success") if %w[success failure].include?(result)
    from_date = parse_date(from)
    to_date = parse_date(to)
    scope = scope.where(created_at: from_date.beginning_of_day..) if from_date
    scope = scope.where(created_at: ..to_date.end_of_day) if to_date
    scope
  end

  def self.parse_date(value)
    Time.zone.parse(value.to_s)&.to_date if value.present?
  rescue ArgumentError
    nil
  end
  private_class_method :parse_date
end
