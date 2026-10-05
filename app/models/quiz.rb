# 小テスト（保存しない）。単語帳・範囲・問題数を検証し、範囲内から重複なしで抽選する。
class Quiz
  include ActiveModel::Model
  include ActiveModel::Attributes

  MIN_COUNT = 10
  MAX_COUNT = 50

  attribute :wordbook
  attribute :start_no, :integer
  attribute :end_no, :integer
  attribute :span, :integer # 開始から何語か。あれば end_no は span から計算する（単語帳の最後で止める）
  attribute :count, :integer

  SPAN_CHOICES = [ 50, 100, 200, 300, 500 ].freeze
  DEFAULT_SPAN = 100

  validate :check_range_and_count

  def self.defaults_for(wordbook)
    available = wordbook.words_count
    new(wordbook: wordbook, start_no: wordbook.min_number, end_no: wordbook.max_number,
        count: [ [ 30, available ].min, MIN_COUNT ].max)
  end

  # 重複なしで抽選する。並びは抽選順のまま（番号は単語帳の見出し番号を添える）
  def draw
    words_in_range.sample(count)
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

  # 開始 + 語数 − 1。単語帳の最後を超えるときは最後で止める
  def self.end_for(start_no, span, max)
    [ start_no + span - 1, max ].min
  end

  # 最後の番号で止めたか（画面に「最後の番号までにしました」と出す）
  def clamped?
    span.present? && start_no.present? && start_no + span - 1 > wordbook.max_number
  end

  private
    def check_range_and_count
      min, max = wordbook.min_number, wordbook.max_number
      range_ok = true

      unless whole_number?(:start_no) && start_no.between?(min, max)
        errors.add(:start_no, "#{min}〜#{max}の数字を入れてください")
        range_ok = false
      end

      if !span_given? && end_no.nil?
        errors.add(:span, "1以上の数字を入れてください")
        range_ok = false
      elsif span_given?
        if whole_number?(:span) && span >= 1
          self.end_no = self.class.end_for(start_no, span, max) if range_ok
        else
          errors.add(:span, "1以上の数字を入れてください")
          range_ok = false
        end
      else
        # 終わりの番号を直接受け取る従来の形（直接の POST 用）
        if end_no.nil?
          errors.add(:end_no, "数字で入力してください")
          range_ok = false
        elsif end_no < min || end_no > max
          errors.add(:end_no, "#{min}〜#{max} の範囲で入力してください")
          range_ok = false
        elsif range_ok && start_no > end_no
          errors.add(:start_no, "開始は終了以下にしてください")
          range_ok = false
        end
      end

      if count.nil? || count < MIN_COUNT || count > MAX_COUNT
        errors.add(:count, "問題数は #{MIN_COUNT}〜#{MAX_COUNT} で指定してください")
      elsif range_ok && count > available_count
        errors.add(:count, "範囲内の語数（#{available_count}語）を超えています")
      end
    end

    def raw_input(name) = @attributes[name].value_before_type_cast

    def span_given?
      !raw_input("span").to_s.strip.empty?
    end

    # 「12.5」「abc」のような値は、整数に丸められる前の入力で弾く
    def whole_number?(attr)
      value = public_send(attr)
      raw = raw_input(attr.to_s)
      !value.nil? && raw.to_s.strip.match?(/\A\d+\z/)
    end
end
