module Gemini
  # 待ってやり直せば成功しうるもの（429 の分あたり上限、5xx、タイムアウト）
  class Retryable < Error; end
end
