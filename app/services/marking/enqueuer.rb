module Marking
  # 領域を構造化の順番待ち（queued）にして、ジョブを積む。積むだけで、すぐ返す。
  module Enqueuer
    module_function

    # GEMINI_API_KEY が無いときは何もしない（confirmed のまま）
    def call(regions)
      return 0 unless GeminiConfig.configured?

      count = 0
      regions.find_each do |region|
        region.update!(status: :queued, error_message: nil) unless region.queued?
        Marking::ExtractJob.perform_later(region.id)
        count += 1
      end
      count
    end
  end
end
