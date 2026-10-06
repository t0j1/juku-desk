class QuestionFolderUpload < ApplicationRecord
  belongs_to :question_folder
  belongs_to :upload

  validates :upload_id, uniqueness: { scope: :question_folder_id }
end
