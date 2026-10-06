# 取り込んだ画像の、承認済みの問題から N 問をランダムに選んで小テストを作る。
# new＝選んだ問題のプレビュー（開くたび・「選び直す」で再抽選）、create＝プレビューの問題でそのまま作成。
class UploadRandomTestsController < ApplicationController
  before_action :require_writer!
  before_action :set_upload

  def new
    @count = requested_count
    pool = pool_scope.to_a
    @questions = pool.sample(@count)
    @available = pool.size
    @title = "画像 ##{@upload.id} のランダム"
  end

  def create
    ids = Array(params[:question_ids]).map(&:to_i)
    builder = Marking::TestBuilder.new(title: params[:title], count: requested_count)
    builder.question_ids = pool_scope.where(id: ids).pluck(:id) & ids # この画像の承認済みの問題だけ
    if builder.save(current_user)
      AuditLog.record!(:create, builder.test, metadata: { count: builder.test.items.size, upload_id: @upload.id })
      redirect_to marking_test_path(builder.test), status: :see_other
    else
      redirect_to new_upload_random_test_path(@upload, count: requested_count), alert: builder.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def require_writer!
      redirect_to uploads_path, alert: "閲覧のみの権限では作成できません。" unless current_user.can_write?
    end

    def set_upload = @upload = Upload.find(params[:upload_id])

    def pool_scope = Question.approved.where(region_id: @upload.crop_regions.select(:id)).order(:id)

    def requested_count = params[:count].to_i.clamp(1, Marking::QuestionPicker.max_count).then { |n| params[:count].present? ? n : 5 }
end
