class Word < ApplicationRecord
  belongs_to :wordbook, counter_cache: true

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :wordbook_id }
  validates :term, :meaning, presence: true

  # 品詞記号。[人・物] のような本文中の角括弧と区別するため、品詞だけを数える
  NEXT_PART_OF_SPEECH = /\s\[(?:自|他|名|形|副|前|接|助|代|冠|間|動)\]/

  # 解答用紙に出す意味。最初の意味（①）だけにして、先頭の品詞記号（[他] など）は残す
  def short_meaning
    first = meaning.split("②", 2).first.split(NEXT_PART_OF_SPEECH, 2).first
    first.sub("①", "").squish
  end
end
