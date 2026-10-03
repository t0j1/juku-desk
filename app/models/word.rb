class Word < ApplicationRecord
  belongs_to :wordbook, counter_cache: true

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :wordbook_id }
  validates :term, :meaning, presence: true

  # 解答用紙に出す意味。最初の意味（①）だけにして、品詞記号（[他] など）は残す
  def short_meaning
    first = meaning.split("②", 2).first
    first = first.sub(/(\s*\[[^\]]+\])+\s*\z/, "") # 次の意味の品詞記号が残らないように
    first.sub("①", "").squish
  end
end
