# 進捗の仕組みを確かめるためのダミージョブ。steps 回まわし、1 回ごとに block（あれば）を呼ぶ。
class DummyProgressJob < ApplicationJob
  cattr_accessor :on_step, :cancelled_calls, default: nil

  def perform(progress_id, steps = 10)
    JobProgress.find(progress_id).run(total: steps, on_cancel: -> { self.class.cancelled_calls = (self.class.cancelled_calls || 0) + 1 }) do |p|
      steps.times do |i|
        on_step&.call(i + 1)
        p.step!(i + 1, "#{i + 1}件目")
      end
    end
  end
end
