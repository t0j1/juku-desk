# 問題フォルダ内の全画像の問題から、1画面で小テストを作る（UploadOneStopTestsController と同じ流れ）。
class FolderOneStopTestsController < UploadOneStopTestsController
  private
    def set_source = @source = QuestionFolder.find(params[:question_folder_id])

    def pool_scope = source.reviewable_questions

    def new_path = new_question_folder_one_stop_test_path(source)

    def create_path = question_folder_one_stop_test_path(source)

    def back_path = question_folder_path(source)

    def source_label = "フォルダ「#{source.name}」"
end
