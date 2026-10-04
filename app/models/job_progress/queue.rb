# まだ実行されていないジョブをキューから取り除く。実行が始まっていれば false（ジョブ側のキャンセル確認に任せる）
module JobProgress::Queue
  def self.remove(active_job_id)
    return false if active_job_id.blank?

    adapter = ActiveJob::Base.queue_adapter
    if adapter.respond_to?(:enqueued_jobs) # テスト用アダプタ
      adapter.enqueued_jobs.reject! { |j| (j["job_id"] || j[:job_id]) == active_job_id }
      true
    else
      job = SolidQueue::Job.find_by(active_job_id: active_job_id)
      # 実行中（claimed）や完了済みは外せない
      return false if job.nil? || job.finished? || job.claimed?
      job.destroy!
      true
    end
  end
end
