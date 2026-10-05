module PrintJobsHelper
  STAPLES = [ "なし", "左上", "右上", "2か所" ].freeze

  DUPLEXES = [ [ "指定なし", "" ], [ "長辺とじ", "long" ], [ "短辺とじ", "short" ] ].freeze

  def print_job_pill(job)
    case job.status
    when "pending" then status_pill("待機中", :busy)
    when "leased" then status_pill("印刷中", :busy)
    when "acknowledged" then status_pill("印刷済み", :ok)
    when "failed" then status_pill("失敗", :ng)
    when "expired" then status_pill("期限切れ", :ng)
    else status_pill("取り消し", :neutral)
    end
  end
end
