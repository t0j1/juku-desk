# ジョブの中から進み具合を書き込む。毎ページ DB に書くと Neon / Render の負荷になるため、
# 保存は最短 2 秒おきに間引く。キャンセルの確認も同じタイミングで行う（反応まで最大 2 秒）。
#
#   progress.run(total: pages.size) do |p|
#     pages.each_with_index { |page, i| work(page); p.step!(i + 1, "#{i + 1}ページ目") }
#   end
module ProgressReporting
  extend ActiveSupport::Concern

  class Cancelled < StandardError; end

  included do
    class_attribute :save_interval, default: 2.seconds
  end

  # 開始〜完了までを包む。キャンセルされたら status を cancelled にして静かに終わる（例外は外に出さない）。
  # 途中までのデータの扱いは呼び出し側が on_cancel で決める。
  def run(total: nil, on_cancel: nil)
    start!(total: total)
    yield self
    succeed!
  rescue Cancelled
    on_cancel&.call
    finish!(:cancelled)
  rescue StandardError => e
    finish!(:failed, message: e.message.truncate(300))
    raise
  end

  def start!(total: nil)
    raise Cancelled if cancel_requested?
    update!(status: :running, total: total, done: 0, started_at: Time.current, finished_at: nil)
    @saved_at = monotonic_now
  end

  # n 件目まで終わった。保存は間引き、保存のついでにキャンセル要求を読み直す
  def step!(n, message = nil)
    self.done = n
    self.message = message if message
    return unless @saved_at.nil? || monotonic_now - @saved_at >= save_interval

    flush!
    raise Cancelled if cancel_requested?
  end

  # 区切りの良いところ（結果を確定する直前など）で、間引きを待たずにキャンセル要求を確かめる
  def check_cancel!
    flush!
    raise Cancelled if cancel_requested?
  end

  # 間引きを待たずにすぐ保存する（区切りの良いところで）
  def flush!
    @saved_at = monotonic_now
    update_columns(done: done, message: message, updated_at: Time.current)
    self.cancel_requested_at, db_status = self.class.where(id: id).pick(:cancel_requested_at, :status)
    revive! if db_status == "failed" && self.status.to_s == "running" # 生きていたのに止まったと見なされた
  end

  # 実際の状態が優先：止まったと見なして failed にされた後でもジョブが動き続けていたら、実行中に戻す
  # （対象も、止まったと見なされた時に failed にされていたなら、処理中に戻す）。完了は succeed! がそのまま上書きする
  def revive!
    update_columns(status: self.class.statuses[:running], finished_at: nil, message: nil)
    subject.try(:progress_revived!, self)
  end

  # total が後から分かる処理のため
  def total!(n)
    update_columns(total: n, updated_at: Time.current)
  end

  # 止まったと見なされた後に実際は完了していた場合も、こちらが勝つ（対象は呼び出し側が done にする）
  def succeed!
    self.done = total if total
    finish!(:succeeded)
  end

  def finish!(new_status, message: self.message)
    update!(status: new_status, message: message, finished_at: Time.current)
  end

  private
    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
