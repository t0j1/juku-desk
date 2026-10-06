# フォルダに画像を入れる／外す（画像と問題そのものは変わらない）
class QuestionFolderUploadsController < ApplicationController
  before_action :require_writer!
  before_action :set_folder

  def create
    upload = Upload.find(params[:upload_id])
    @folder.folder_uploads.find_or_create_by!(upload: upload)
    redirect_to question_folder_path(@folder), notice: "画像 ##{upload.id} をフォルダに入れました。", status: :see_other
  end

  def destroy
    @folder.folder_uploads.where(upload_id: params[:id]).destroy_all
    redirect_to question_folder_path(@folder), notice: "画像 ##{params[:id]} をフォルダから外しました。", status: :see_other
  end

  private
    def set_folder = @folder = QuestionFolder.find(params[:question_folder_id])

    def require_writer!
      redirect_to question_folders_path, alert: "閲覧のみの権限では変更できません。" unless current_user.can_write?
    end
end
