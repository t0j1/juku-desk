# 取り込んだ画像の全問題（未承認も含む）を、形式別の大問・小問の最終の並びで確認し、そのまま承認・小テスト作成・印刷へ進む。
# new＝1画面のプレビュー（各問題にチェック。初期は全部オン）、create＝チェックした問題のうち未承認のものを承認して、形式別の小テストを作る。
# 問題フォルダ版（FolderOneStopTestsController）は、対象と戻り先を差し替えるだけ。
class UploadOneStopTestsController < ApplicationController
  before_action :require_writer!
  before_action :set_source

  helper_method :source, :create_path, :back_path, :source_label

  def new
    @title = "#{source_label}の小テスト"
    @entries = Marking::SectionNumbering.new(pool_scope.includes(region: :upload).order(:id).to_a, Marking::SectionNumbering.normalize_order(nil)).entries
    @instructions = SectionTemplate.instructions
  end

  def create
    ids = Array(params[:question_ids]).map(&:to_i).uniq
    chosen = ids.filter_map { |id| pool_by_id[id] }.select { |q| q.approved? || q.approvable? } # 承認できない問題（科目・問題文・解答が未入力）は含めない
    builder = Marking::TestBuilder.new(title: params[:title], count: [ chosen.size, 1 ].max, group_by_type: true)
    builder.question_ids = chosen.map(&:id)
    pending = chosen.reject(&:approved?)

    saved = false
    Question.transaction do
      pending.each { |q| q.approve!(current_user) }
      saved = builder.save(current_user)
      raise ActiveRecord::Rollback unless saved
    end

    if saved
      AuditLog.record!(:create, builder.test, metadata: { count: builder.test.items.size, source: source.class.name, source_id: source.id, one_stop: true, approved_count: pending.size })
      redirect_to print_marking_test_path(builder.test, kind: "question", both: 1), notice: "小テストを作りました（#{pending.size} 問を承認しました）。AI 作成の解答は、印刷の前に確認してください。", status: :see_other
    else
      redirect_to new_path, alert: builder.errors.full_messages.to_sentence.presence || "小テストを作れませんでした。", status: :see_other
    end
  end

  private
    attr_reader :source

    def require_writer!
      redirect_to uploads_path, alert: "閲覧のみの権限では作成できません。" unless current_user.can_write?
    end

    def set_source = @source = Upload.find(params[:upload_id])

    def pool_scope = Question.reviewable.where(region_id: source.crop_regions.select(:id))

    def pool_by_id = @pool_by_id ||= pool_scope.index_by(&:id)

    def new_path = new_upload_one_stop_test_path(source)

    def create_path = upload_one_stop_test_path(source)

    def back_path = upload_path(source)

    def source_label = "画像 ##{source.id}"
end
