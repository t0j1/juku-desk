require "test_helper"
require Rails.root.join("db/seeds/wordbook_seed")

class WordbookSeedTest < ActiveSupport::TestCase
  SAMPLE = Rails.root.join("db/seeds/sample_wordbook.csv").to_s

  FakeHttp = Struct.new(:response) do
    def get_response(_uri) = response
  end

  def run_seed(env, http: nil)
    WordbookSeed.run(env: env, logger: StringIO.new, http: http || FakeHttp.new(nil))
  end

  test "skips without error when neither path nor url is set" do
    assert_no_difference "Wordbook.count" do
      assert_equal :skipped, run_seed({ "WORDBOOK_SEED_NAME" => "サンプル" })
    end
  end

  test "imports from WORDBOOK_SEED_PATH" do
    assert_equal :imported, run_seed({ "WORDBOOK_SEED_PATH" => SAMPLE, "WORDBOOK_SEED_NAME" => "サンプル" })
    assert_equal 10, Wordbook.find_by!(name: "サンプル").words_count
  end

  test "does nothing when the wordbook already exists" do
    assert_no_difference "Word.count" do
      assert_equal :exists, run_seed({ "WORDBOOK_SEED_PATH" => SAMPLE, "WORDBOOK_SEED_NAME" => wordbooks(:leap).name })
    end
  end

  test "defaults the name to LEAP 改訂版" do
    Wordbook.where(name: "LEAP 改訂版").destroy_all
    run_seed({ "WORDBOOK_SEED_PATH" => SAMPLE })
    assert Wordbook.exists?(name: "LEAP 改訂版")
  end

  test "rejects a non-https url before fetching" do
    assert_raises(ArgumentError) { run_seed({ "WORDBOOK_SEED_URL" => "http://example.com/a.csv", "WORDBOOK_SEED_NAME" => "サンプル" }) }
  end

  test "imports from WORDBOOK_SEED_URL" do
    csv = File.binread(SAMPLE)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, csv)
    assert_equal :imported, run_seed({ "WORDBOOK_SEED_URL" => "https://storage.example.com/w.csv", "WORDBOOK_SEED_NAME" => "サンプル" }, http: FakeHttp.new(response))
    assert_equal 10, Wordbook.find_by!(name: "サンプル").words_count
  end

  test "raises without leaking the url when the download fails" do
    response = Net::HTTPForbidden.new("1.1", "403", "Forbidden")
    error = assert_raises(RuntimeError) do
      run_seed({ "WORDBOOK_SEED_URL" => "https://storage.example.com/w.csv?sig=secret", "WORDBOOK_SEED_NAME" => "サンプル" }, http: FakeHttp.new(response))
    end
    assert_no_match(/secret/, error.message)
  end
end
