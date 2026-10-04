module Marking
  # 取り込み済みの問題を、領域ごとにまとめて構造化し直す（#33 の LaTeX 化・#49 の問題形式より前に取り込んだもの向け）。
  # 構造化は既存の ExtractJob（Gemini の同時 1 件・RPM・日次上限の保留）に順番待ちとして積むだけ。
  # 作り直すと、その領域の問題（小テストで使っていないもの）は置き換わり、承認も外れる。
  module BulkRestructure
    module_function

    # 未対応の問題：英語なのに question_type が null のもの、または今の形式（answer_in_material あり）より前の応答から作ったもの。
    # 今のプロンプト（LaTeX・問題形式・解答の出どころ）より前に作った問題は、raw_ai.response に answer_in_material が無い
    def outdated_questions
      Question.reviewable.where(subject: "英語", question_type: nil)
              .or(Question.reviewable.where.not("questions.raw_ai -> 'response' ? 'answer_in_material'"))
    end

    # 対象にできる領域（構造化が終わっていて、小テストで使っている問題を含まないもの）。
    # 小テストで使っている問題は消せないため、作り直すと同じ問題が重複するので対象外にする
    def regions_for(questions)
      region_ids = questions.reorder(nil).distinct.pluck(:region_id)
      CropRegion.where(id: region_ids, status: %w[extracted needs_review])
                .where.not(id: Question.where(id: ExamItem.select(:question_id)).select(:region_id))
    end

    # 作り直すと承認が外れる問題（対象の領域にある承認済みの問題。選んでいない問題も同じ領域なら含む）
    def approved_in(regions) = Question.approved.where(region_id: regions.select(:id))

    def enqueue!(regions, user:)
      ids = regions.order(:id).ids
      return [ nil, nil ] if ids.empty?

      batch = RestructureBatch.create!(user: user, region_ids: ids)
      progress = Marking::Enqueuer.call(CropRegion.where(id: ids).order(:id), user: user, title: "まとめて再構造化（#{ids.size}件）", label: "再構造化中", subject: batch)
      [ batch, progress ]
    end
  end
end
