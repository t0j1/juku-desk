# 時間のかかる処理 1 件ぶんの進み具合。ジョブ側の書き込みは ProgressReporting、画面側は ProgressesController。
class JobProgress < ApplicationRecord
  include ProgressReporting

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4 }, default: :queued

  validates :kind, :title, presence: true

  scope :active, -> { where(status: %i[ queued running ]) }
  # 終わったものも、画面が結果を表示し終えるまでの間は返す
  scope :recent, -> { where("finished_at IS NULL OR finished_at > ?", 2.minutes.ago) }

  # 進捗の行を作ってジョブを積む。ジョブの第 1 引数は進捗の id（残りは args）。
  def self.enqueue(job_class, *args, user:, kind:, title:, subject: nil, total: nil)
    progress = create!(user: user, kind: kind, title: title, subject: subject, total: total)
    job = job_class.perform_later(progress.id, *args)
    progress.update_columns(active_job_id: job.job_id)
    progress
  end

  # ワーカーごと落ちると run の rescue が走らず running のまま残る。進捗は数秒おきに updated_at が進むので、
  # しばらく止まったものは failed に倒す（モーダルが「処理中」のまま永久に残らないように）
  STALE_AFTER = 5.minutes # 1 チャンク（25ページの抽出など）が重くても、生きているジョブを止まったと見なさない長さ

  STALE_MESSAGE = "処理が途中で止まりました。もう一度お試しください。"

  # 止まったと見なして failed にしたもの。ジョブが実は生きていた場合、あとで実際の状態（実行中・完了）に戻る
  def stale_failed? = failed? && message == STALE_MESSAGE

  def fail_if_stale!
    return unless running? && updated_at < STALE_AFTER.ago
    update!(status: :failed, finished_at: Time.current, message: STALE_MESSAGE)
    subject.try(:progress_failed!, self) # 対象が処理中のまま取り残されないようにする
  end

  def finished? = succeeded? || failed? || cancelled?

  def cancel_requested? = cancel_requested_at.present?

  # total が分からないときは nil（画面は「処理中（経過 m:ss）」にする）
  def percent
    return 100 if succeeded?
    return unless total&.positive?
    [ (done * 100.0 / total).floor, 99 ].min
  end

  def elapsed_seconds
    return 0 unless started_at
    ((finished_at || Time.current) - started_at).to_i
  end

  # 残りの目安（秒）。まだ 1 件も進んでいない／total が不明なら nil
  def eta_seconds
    return unless running? && total&.positive? && done.positive?
    (elapsed_seconds * (total - done).to_f / done).ceil
  end

  # キャンセルを受け付ける。まだ動いていなければキューから外してその場で cancelled にする。
  # 動いているものは、ジョブが次の区切りで気づいて止まる。
  def request_cancel!
    return if finished?
    update!(cancel_requested_at: Time.current) unless cancel_requested?
    return unless queued?

    if JobProgress::Queue.remove(active_job_id)
      update!(status: :cancelled, finished_at: Time.current, message: "キャンセルしました")
      subject.try(:progress_cancelled!, self) # ジョブが動かないので、対象の後始末はここで行う
    end
  end

  def as_progress_json
    { id: id, kind: kind, subject_type: subject_type, subject_id: subject_id, title: title, status: status, total: total, done: done, percent: percent, message: message,
      elapsed_seconds: elapsed_seconds, eta_seconds: eta_seconds, cancel_requested: cancel_requested?, finished: finished?, stale: stale_failed? }
  end
end
