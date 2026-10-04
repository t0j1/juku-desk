module Gemini
  # GEMINI_MODEL のモデルが廃止・利用不可（404）。待っても直らないので、通常のエラーとは分けて扱う
  class ModelUnavailable < Error; end
end
