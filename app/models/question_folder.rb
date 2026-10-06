# 問題フォルダ。複数の取り込み画像（Upload）をまとめる（画像は複数のフォルダに入れてよい）。消しても画像・問題は残る。
class QuestionFolder < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :folder_uploads, class_name: "QuestionFolderUpload", dependent: :delete_all
  has_many :uploads, through: :folder_uploads

  validates :name, presence: true, length: { maximum: 100 }

  # 出題の対象になる承認済みの問題（フォルダ内の全画像ぶん）
  def approved_questions = Question.approved.where(region_id: CropRegion.where(upload_id: folder_uploads.select(:upload_id)).select(:id))
end
