# 問題フォルダ：複数の取り込み画像をまとめる。作成・名前変更・削除（画像と問題は消えない）、フォルダ内の問題から小テストを作る入口。
class QuestionFoldersController < ApplicationController
  before_action :require_writer!, only: %i[ create update destroy extract_whole ]
  before_action :set_folder, only: %i[ show update destroy extract_whole ]

  def index
    @folders = QuestionFolder.includes(:folder_uploads).order(:name, :id)
  end

  def create
    folder = QuestionFolder.new(name: params.dig(:question_folder, :name).to_s.strip, created_by: current_user)
    if folder.save
      redirect_to question_folder_path(folder), notice: "フォルダ「#{folder.name}」を作りました。", status: :see_other
    else
      redirect_to question_folders_path, alert: folder.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def show
    @uploads = @folder.uploads.includes(crop_regions: :questions).order("question_folder_uploads.id")
    @addable = Upload.where.not(id: @folder.folder_uploads.select(:upload_id)).order(id: :desc).limit(200)
    @approved = @folder.approved_questions.includes(region: :upload).order(:id)
  end

  # フォルダ内の、領域が 0 件の画像を、ページ全体を 1 領域にして構造化の順番待ちに積む
  def extract_whole
    return redirect_to question_folder_path(@folder), alert: "GEMINI_API_KEY が設定されていません。", status: :see_other unless GeminiConfig.configured?

    uploads = @folder.uploads.where.not(id: CropRegion.select(:upload_id)).to_a
    regions = uploads.filter_map(&:add_whole_region!)
    return redirect_to question_folder_path(@folder), alert: "領域が 0 件の画像はありません。", status: :see_other if regions.empty?

    progress = Marking::Enqueuer.call(CropRegion.where(id: regions.map(&:id)), generate_answers: params[:generate_answers].nil? || ActiveModel::Type::Boolean.new.cast(params[:generate_answers]),
                                      user: current_user, title: "フォルダ「#{@folder.name}」の構造化（ページ全体）", subject: @folder)
    AuditLog.record!(:update, @folder, metadata: { whole_page: regions.size })
    open_progress(progress) if progress
    redirect_to question_folder_path(@folder), notice: "領域が 0 件の画像 #{regions.size} 枚を、ページ全体で構造化の順番待ちに入れました。", status: :see_other
  end

  def update
    if @folder.update(name: params.dig(:question_folder, :name).to_s.strip)
      redirect_to question_folder_path(@folder), notice: "名前を変えました。", status: :see_other
    else
      redirect_to question_folder_path(@folder), alert: @folder.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @folder.destroy!
    redirect_to question_folders_path, notice: "フォルダ「#{@folder.name}」を削除しました（画像と問題は残っています）。", status: :see_other
  end

  private
    def set_folder = @folder = QuestionFolder.find(params[:id])

    def require_writer!
      redirect_to question_folders_path, alert: "閲覧のみの権限では変更できません。" unless current_user.can_write?
    end
end
