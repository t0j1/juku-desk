class Word < ApplicationRecord
  belongs_to :wordbook, counter_cache: true

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :wordbook_id }
  validates :term, :meaning, presence: true
end
