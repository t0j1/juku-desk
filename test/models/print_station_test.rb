require "test_helper"

class PrintStationTest < ActiveSupport::TestCase
  test "the unique index on name rejects a duplicate even when validations are skipped" do
    PrintStation.register!(name: "教室A")
    dup = PrintStation.new(name: "教室A", token_digest: PrintStation.digest("x"), token_issued_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "register! turns a unique violation that slipped past the validation into a name error" do
    PrintStation.register!(name: "教室A")
    station = PrintStation.new(name: "教室A")
    station.define_singleton_method(:valid?) { |*| true } # 同時登録で、チェックの時点ではまだ同名がなかった状態を再現する
    PrintStation.define_singleton_method(:new) { |*, **| station }
    begin
      error = assert_raises(ActiveRecord::RecordInvalid) { PrintStation.register!(name: "教室A") }
    ensure
      PrintStation.singleton_class.remove_method(:new)
    end
    assert_equal station, error.record
    assert error.record.errors.of_kind?(:name, :taken)
    assert_equal 1, PrintStation.where(name: "教室A").count
  end

  test "reissuing a revoked station makes it active again" do
    station, = PrintStation.register!(name: "教室A")
    station.revoke!
    assert_nil PrintStation.authenticate("anything")
    token = station.reissue_token!
    assert_nil station.reload.revoked_at
    assert_equal station, PrintStation.authenticate(token)
  end
end

# 同時登録は別スレッド・別接続でないと再現できないので、テストのトランザクションを使わない
class PrintStationConcurrentRegistrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown { PrintStation.where(name: "同時登録").delete_all }

  test "of the same name registered at once, exactly one succeeds and the rest are ordinary validation errors" do
    start = Queue.new
    results = Array.new(5) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          PrintStation.register!(name: "同時登録")
          :ok
        rescue ActiveRecord::RecordInvalid
          :invalid
        end
      end
    end.tap { 5.times { start << true } }.map(&:value)

    assert_equal 1, results.count(:ok)
    assert_equal 4, results.count(:invalid)
    assert_equal 1, PrintStation.where(name: "同時登録").count
  end
end
