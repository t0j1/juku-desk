# 将来の弱点出題用（誰がどの問題に正解・不正解したか）。今回はテーブルだけで、記録はしない。
class AnswerEvent < ApplicationRecord
  belongs_to :question
  belongs_to :student, optional: true
end
