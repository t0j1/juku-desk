class Wordbook < ApplicationRecord
  has_many :words, -> { order(:number) }, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  def min_number = words.minimum(:number)
  def max_number = words.maximum(:number)
end
