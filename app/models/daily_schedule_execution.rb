# 定時タスクの 1 回分の実行記録。予定時刻（scheduled_at）と、実際に動いた時刻（executed_at）は別に持つ。
# 動けなかったときも「未実行」として残し、成功には見せない。(task, 予定時刻) は一意なので、同じ回は 2 度動かない。
class DailyScheduleExecution < ApplicationRecord
  STATUSES = %w[ executed draft_saved skipped failed not_run ].freeze
  # 状態 → [ピルの文字, 色の種類]
  PILLS = {
    "executed" => [ "実行済み", :ok ],
    "draft_saved" => [ "下書き保存済み", :busy ],
    "skipped" => [ "未実行（スキップ）", :warn ],
    "failed" => [ "失敗", :ng ],
    "not_run" => [ "未実行", :warn ]
  }.freeze

  belongs_to :daily_schedule_task
  belongs_to :print_job, optional: true

  validates :scheduled_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  def pill = PILLS.fetch(status)
end
