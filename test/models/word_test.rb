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

  test "every meaning in the seed list yields a non-empty short meaning" do
    rows = CSV.read(Rails.root.join("db/seeds/leap_modified_list.csv"), headers: true, encoding: "bom|utf-8")
    assert_equal 2300, rows.size
    assert rows.all? { |r| Word.new(meaning: r["意味"]).short_meaning.present? }
  end
end
