module Marking
  # 領域 1 件の構造化。Gemini への同時リクエストは GEMINI_MAX_CONCURRENCY（既定 1）件まで（Solid Queue の並行数制限）。
  class ExtractJob < ApplicationJob
    queue_as :default
    limits_concurrency to: GeminiConfig.max_concurrency, key: ->(_region_id) { "gemini" }, duration: 15.minutes
    discard_on ActiveRecord::RecordNotFound

    def perform(region_id)
      Marking::Extractor.call(CropRegion.find(region_id))
    end
  end
end
