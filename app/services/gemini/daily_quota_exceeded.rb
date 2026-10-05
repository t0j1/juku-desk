module Gemini
  # 日次の上限（RESOURCE_EXHAUSTED で quota が PerDay のもの）。待ってもその日のうちは成功しない
  class DailyQuotaExceeded < Error; end
end
