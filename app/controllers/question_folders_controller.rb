# 問題フォルダ：複数の取り込み画像をまとめる。作成・名前変更・削除（画像と問題は消えない）、フォルダ内の問題から小テストを作る入口。
class QuestionFoldersController < ApplicationController
  before_action :require_writer!, only: %i[ create update destroy ]
  before_action :set_folder, only: %i[ show update destroy ]

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
