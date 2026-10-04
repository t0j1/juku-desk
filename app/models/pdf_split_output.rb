class PdfSplitOutput < ApplicationRecord
  belongs_to :pdf_split_job
  has_many :pdf_blobs, dependent: :delete_all
  before_destroy(prepend: true) { PdfBlob.purge(pdf_blobs) }

  validates :display_name, presence: true
  validates :page_from, :page_to, numericality: { only_integer: true, greater_than: 0 }
  validate :range_order

  def filename = "#{display_name}.pdf"
  def pages_label = page_from == page_to ? "p.#{page_from}" : "p.#{page_from}-#{page_to}"

  private
    def range_order
      errors.add(:page_to, "は開始ページ以上にしてください") if page_from && page_to && page_to < page_from
    end
end
