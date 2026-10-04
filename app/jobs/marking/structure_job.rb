module Marking
  # 領域をまとめて 1 件ずつ構造化する（画像 1 枚ぶん、まとめて再構造化の 1 回ぶん）。第 1 引数は JobProgress の id。
  # - 領域ごとに progress.step!（保存は ProgressReporting が数秒おきに間引く）。「構造化中 3/8領域」
  # - キャンセル：まだ処理していない領域は queued のまま残す（あとで「構造化を開始・やり直す」や上限明けの再開で続きを処理できる）。作った問題は残す
  # - 日次上限：Extractor が領域を quota_exceeded にしたら止め、進捗を held（保留）にする。残りは queued のまま、ResumeJob が上限明けに再開する
  # Gemini への同時リクエストは GEMINI_MAX_CONCURRENCY（既定 1）件まで。1 回で何十件も処理することがあるので、ExtractJob より長く押さえる
  class StructureJob < ApplicationJob
    queue_as :default
    limits_concurrency to: GeminiConfig.max_concurrency, key: ->(*) { "gemini" }, duration: 1.hour
    discard_on ActiveRecord::RecordNotFound

    def perform(progress_id, region_ids, label = "構造化中")
      progress = JobProgress.find(progress_id)
      progress.start!(total: region_ids.size)
      region_ids.each_with_index do |id, i|
        progress.flush! # 1 件の Gemini 待ちが長くても、止まったとは見なされないように
        region = CropRegion.find_by(id: id)
        Marking::Extractor.call(region) if region
        return hold(progress, region_ids.drop(i)) if region&.reload&.quota_exceeded? || GeminiQuota.exceeded?

        progress.step!(i + 1, "#{label} #{i + 1}/#{region_ids.size}領域")
      end
      progress.succeed!
    rescue ProgressReporting::Cancelled
      progress.finish!(:cancelled, message: "キャンセルしました（作った問題は残しています）")
    rescue StandardError => e
      progress&.finish!(:failed, message: e.message.truncate(300)) unless progress&.finished?
      raise
    end

    private
      # 上限に達した：残り（この領域を含む、まだ終わっていないもの）は保留。上限明けに ResumeJob が続きを処理する
      def hold(progress, rest_ids)
        rest = CropRegion.where(id: rest_ids).waiting.count
        resume_at = GeminiQuota.resume_at&.in_time_zone("Asia/Tokyo")
        when_text = resume_at ? I18n.l(resume_at, format: "%-m月%-d日 %H:%M") : "上限のリセット後"
        progress.flush!
        progress.finish!(:held, message: "上限に達しました。残り#{rest}件は#{when_text}（JST）に自動で再開します")
      end
  end
end
