module Marking
  # 領域を構造化の順番待ち（queued）にして、ジョブを積む。積むだけで、すぐ返す。
  module Enqueuer
    module_function

    # GEMINI_API_KEY が無いときは何もしない（confirmed のまま）
    # generate_answers: 「解答を AI で作る」の選択。nil なら領域に保存済みの選択のまま（日次上限からの再開など）
    def call(regions, generate_answers: nil)
      return 0 unless GeminiConfig.configured?

      count = 0
      regions.find_each do |region|
        attrs = { status: :queued, error_message: nil }
        attrs[:generate_answers] = generate_answers unless generate_answers.nil?
        region.update!(attrs) unless region.queued? && generate_answers.nil?
        Marking::ExtractJob.perform_later(region.id)
        count += 1
      end
      count
    end
  end
end
