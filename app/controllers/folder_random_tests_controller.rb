# 問題フォルダ内の全画像の承認済みの問題から小テストを作る（ランダム・手動選択の両方。UploadRandomTestsController と同じ流れ）。
class FolderRandomTestsController < UploadRandomTestsController
  private
    def set_source = @source = QuestionFolder.find(params[:question_folder_id])

    def pool_scope = source.approved_questions.order(:id)

    def new_path(**opts) = new_question_folder_random_test_path(source, **opts)

    def create_path = question_folder_random_test_path(source)

    def source_label = "フォルダ「#{source.name}」"
end
