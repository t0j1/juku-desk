module Marking
  # 日次上限のリセット後に、保留していた領域（quota_exceeded / queued）の処理を再開する。
  class ResumeJob < ApplicationJob
    queue_as :default

    def perform
      return if GeminiQuota.exceeded? # まだリセット前（時刻の取り違えなど）なら何もしない。次のリセットで再度予約される

      CropRegion.where(status: "quota_exceeded").or(CropRegion.stale_processing).update_all(status: "queued", updated_at: Time.current)
      Marking::Enqueuer.call(CropRegion.where(status: "queued").order(:id), title: "構造化の再開（上限明け）")
    end
  end
end
