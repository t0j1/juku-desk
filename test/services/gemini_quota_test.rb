require "test_helper"

class GeminiQuotaTest < ActiveSupport::TestCase
  teardown do
    reset_gemini
    travel_back
  end

  test "the token bucket spaces calls at 60/RPM seconds" do
    ENV["GEMINI_RPM"] = "10"
    now = Time.zone.local(2026, 10, 5, 12, 0, 0)
    assert_equal 0.0, GeminiQuota.acquire(now: now)
    wait = GeminiQuota.acquire(now: now)
    assert_in_delta 6.0, wait, 0.001
    assert_equal 0.0, GeminiQuota.acquire(now: now + 6)
    assert_in_delta 3.0, GeminiQuota.acquire(now: now + 9), 0.001
  end

  test "the daily counter stops at RPD and resets at midnight Pacific time" do
    ENV["GEMINI_RPM"] = "6000"
    ENV["GEMINI_RPD"] = "3"
    now = Time.utc(2026, 10, 5, 20, 0, 0) # 太平洋時間 13:00（PDT）
    3.times { |i| assert_equal 0.0, GeminiQuota.acquire(now: now + i) }
    assert_raises(GeminiQuota::DailyLimit) { GeminiQuota.acquire(now: now + 10) }

    reset = GeminiQuota.next_reset(now)
    assert_equal Time.utc(2026, 10, 6, 7, 0, 0), reset.utc # 太平洋時間 0:00 = UTC 7:00（PDT）
    assert_equal 0.0, GeminiQuota.acquire(now: reset + 1)
  end

  test "trip! records the day-limit hold once and clears it after the reset" do
    now = Time.utc(2026, 10, 5, 20, 0, 0)
    assert GeminiQuota.trip!(now: now)
    assert_not GeminiQuota.trip!(now: now + 60), "同じ日の 2 回目は新しい停止として数えない"
    assert GeminiQuota.exceeded?(now: now + 3600)
    assert_not GeminiQuota.exceeded?(now: GeminiQuota.resume_at + 1)
    assert_nil GeminiQuota.resume_at
  end
end
