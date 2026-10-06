# 取り込んだ画像の、承認済みの問題から小テストを作る。
# new＝N 問をランダムに選んだプレビュー（開くたび・「選び直す」で再抽選）、create＝送られた問題（プレビューまたは手動で選んだもの）でそのまま作成。
# 問題フォルダ版（FolderRandomTestsController）は、対象と戻り先を差し替えるだけ。
class UploadRandomTestsController < ApplicationController
  before_action :require_writer!
  before_action :set_source

  helper_method :source, :new_path, :create_path, :source_label

  def new
    @count = requested_count
    pool = pool_scope.includes(region: :upload).to_a
    @questions = pool.sample(@count)
    @available = pool.size
    @title = "#{source_label}のランダム"
  end

  def create
    ids = Array(params[:question_ids]).map(&:to_i)
    builder = Marking::TestBuilder.new(title: params[:title], count: requested_count)
    builder.question_ids = pool_scope.where(id: ids).pluck(:id) & ids # 対象の承認済みの問題だけ
    if builder.save(current_user)
      AuditLog.record!(:create, builder.test, metadata: { count: builder.test.items.size, source: source.class.name, source_id: source.id })
      redirect_to marking_test_path(builder.test), status: :see_other
    else
      redirect_to new_path(count: requested_count), alert: builder.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    attr_reader :source

    def require_writer!
      redirect_to uploads_path, alert: "閲覧のみの権限では作成できません。" unless current_user.can_write?
    end

    def set_source = @source = Upload.find(params[:upload_id])

    def pool_scope = Question.approved.where(region_id: source.crop_regions.select(:id)).order(:id)

    def new_path(**opts) = new_upload_random_test_path(source, **opts)

    def create_path = upload_random_test_path(source)

    def source_label = "画像 ##{source.id}"

    def requested_count = params[:count].to_i.clamp(1, Marking::QuestionPicker.max_count).then { |n| params[:count].present? ? n : 5 }
end
