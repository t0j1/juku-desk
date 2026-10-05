module Marking
  # 領域を構造化の順番待ち（queued）にして、まとめて 1 件の StructureJob（進捗つき）を積む。積むだけで、すぐ返す。
  module Enqueuer
    module_function

    # GEMINI_API_KEY が無いとき・対象が無いときは nil（confirmed のまま）。積んだら JobProgress を返す（progress.total が件数）
    # generate_answers: 「解答を AI で作る」の選択。nil なら領域に保存済みの選択のまま（日次上限からの再開など）
    def call(regions, generate_answers: nil, user: nil, title: "構造化", label: "構造化中", subject: nil)
      return unless GeminiConfig.configured?

      ids = []
      regions.find_each do |region|
        attrs = { status: :queued, error_message: nil }
        attrs[:generate_answers] = generate_answers unless generate_answers.nil?
        region.update!(attrs) unless region.queued? && generate_answers.nil?
        ids << region.id
      end
      return if ids.empty?

      JobProgress.enqueue(Marking::StructureJob, ids, label, user: user, kind: "marking_structure", title: title, subject: subject, total: ids.size)
    end
  end
end
