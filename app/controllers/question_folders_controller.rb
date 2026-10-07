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

  # 選んだ（領域が 0 件の）画像を、ページ全体を 1 領域にして構造化の順番待ちに積む
  def extract_whole
    return redirect_to question_folder_path(@folder), alert: "GEMINI_API_KEY が設定されていません。", status: :see_other unless GeminiConfig.configured?

    uploads = @folder.uploads.where(id: Array(params[:upload_ids]).map(&:to_i)).to_a
    result = Marking::WholePage.enqueue(uploads, user: current_user, title: "フォルダ「#{@folder.name}」の構造化（ページ全体）", subject: @folder,
                                        generate_answers: params[:generate_answers].nil? || ActiveModel::Type::Boolean.new.cast(params[:generate_answers]))
    return redirect_to question_folder_path(@folder), alert: "構造化する画像がありません（選んでいないか、すでに領域がある画像です）。", status: :see_other if result[:count].zero?

    AuditLog.record!(:update, @folder, metadata: { whole_page: result[:count] })
    open_progress(result[:progress]) if result[:progress]
    redirect_to question_folder_path(@folder), notice: "#{result[:count]} 枚を順番待ちに入れました。Gemini の日次上限を超えた分は、翌日に自動で再開します。", status: :see_other
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
