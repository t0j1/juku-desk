# 小テスト（保存しない）。単語帳・範囲・問題数を検証し、範囲内から重複なしで抽選する。
class Quiz
  include ActiveModel::Model
  include ActiveModel::Attributes

  MIN_COUNT = 20
  MAX_COUNT = 50

  attribute :wordbook
  attribute :start_no, :integer
  attribute :end_no, :integer
  attribute :count, :integer

  validate :check_range_and_count

  def self.defaults_for(wordbook)
    available = wordbook.words_count
    new(wordbook: wordbook, start_no: wordbook.min_number, end_no: wordbook.max_number,
        count: [ [ 30, available ].min, MIN_COUNT ].max)
  end

  # 重複なしで抽選し、見直しやすいよう単語の番号順に並べる
  def draw
    words_in_range.sample(count).sort_by(&:number)
  end

  def words_in_range
    wordbook.words.where(number: start_no..end_no).to_a
  end

  def available_count
    start_no && end_no ? wordbook.words.where(number: start_no..end_no).count : 0
  end

  # 用紙の左右の語数。奇数のときは左を1語多くする
  def self.split(total)
    left = (total + 1) / 2
    [ left, total - left ]
  end

  def title
    "#{wordbook.name} No.#{start_no}–#{end_no}"
  end

  private
    def check_range_and_count
      min, max = wordbook.min_number, wordbook.max_number
      range_ok = true
      { start_no: start_no, end_no: end_no }.each do |attr, value|
        if value.nil?
          errors.add(attr, "数字で入力してください")
          range_ok = false
        elsif value < min || value > max
          errors.add(attr, "#{min}〜#{max} の範囲で入力してください")
          range_ok = false
        end
      end
      if range_ok && start_no > end_no
        errors.add(:start_no, "開始は終了以下にしてください")
        range_ok = false
      end

      if count.nil? || count < MIN_COUNT || count > MAX_COUNT
        errors.add(:count, "問題数は #{MIN_COUNT}〜#{MAX_COUNT} で指定してください")
      elsif range_ok && count > available_count
        errors.add(:count, "範囲内の語数（#{available_count}語）を超えています")
      end
    end
end
