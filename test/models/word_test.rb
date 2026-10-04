require "test_helper"

class WordTest < ActiveSupport::TestCase
  def short(meaning)
    Word.new(meaning: meaning).short_meaning
  end

  test "short_meaning keeps the part of speech and only the first meaning" do
    assert_equal "[自] 賛成する", short("[自] ①賛成する ②（主語の中で）意見が一致する ③（with ～）（気候，食べ物が）（～に）合う")
  end

  test "short_meaning works when there is only one meaning and no marker" do
    assert_equal "[他] ～に反対する", short("[他] ～に反対する")
  end

  test "short_meaning drops a part-of-speech tag that belongs to the next meaning" do
    assert_equal "[他] （that SV）～と主張する", short("[他] ①（that SV）～と主張する [自] ②（with ～）（～と）言い争う")
  end

  test "short_meaning stops at the next part of speech even without a numbered second meaning" do
    assert_equal "[名] 買い得品<可算>", short("[名] ①買い得品<可算> [自] （商談などで）交渉する")
  end

  test "short_meaning keeps square brackets that are not a part of speech" do
    assert_equal "[名] (for ～)(～の)候補 (者)，(～になりそうな)人 [物]", short("[名] (for ～)(～の)候補 (者)，(～になりそうな)人 [物]")
    assert_equal "[自] (in [at] ～)( ～において)優れている", short("[自] (in [at] ～)( ～において)優れている")
  end

  test "every meaning in the sample wordbook yields a non-empty short meaning" do
    rows = CSV.read(Rails.root.join("db/seeds/sample_wordbook.csv"), headers: true, encoding: "bom|utf-8")
    assert_equal 10, rows.size
    assert rows.all? { |r| Word.new(meaning: r["意味"]).short_meaning.present? }
  end
end
