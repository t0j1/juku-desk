# 過去のパスワード（ハッシュ）。直近 N 回分の再利用を防ぐのに使う。
class PasswordHistory < ApplicationRecord
  belongs_to :user
end
