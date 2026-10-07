module ConsoleHelper
  PILL_SYMBOLS = { ok: "●", busy: "◐", warn: "!", ng: "✕", neutral: "○" }.freeze

  # Status pill: meaning is carried by symbol + text, not color alone.
  def status_pill(label, kind)
    tag.span(class: "pill pill-#{kind}") do
      safe_join([ tag.span(PILL_SYMBOLS.fetch(kind), aria: { hidden: true }), label ])
    end
  end

  SUPPLY_PILLS = { "ok" => [ "十分", :ok ], "low" => [ "少ない", :busy ], "empty" => [ "なし", :ng ] }.freeze

  # 不明（NULL）は「—」
  def supply_pill(status)
    label, kind = SUPPLY_PILLS[status]
    label ? status_pill(label, kind) : "—"
  end

  # 1日のスケジュール: 記録のある回はその状態。記録がなければ、まだ時刻前なら「待機」、過ぎていれば「未実行」（動いていない事実をそのまま出す）
  def daily_status_pill(task, execution, at, now)
    return daily_execution_pill(execution) if execution
    return status_pill("停止中", :neutral) unless task.enabled
    at > now ? status_pill("待機", :neutral) : status_pill("未実行", :warn)
  end

  def daily_execution_pill(execution)
    label, kind = execution.pill
    status_pill(label, kind)
  end

  def pdf_job_pill_kind(job)
    return :ok if job.done?
    return :ng if job.failed?
    return :busy if job.analyzing? || job.splitting? || job.uploaded?
    :neutral
  end

  # サイドバーの項目（config/navigation.yml）。外部リンクも同じタブで開く
  def navigation_groups
    NavigationMenu.build(controller_path:, action_name:)
  end

  def nav_item(label, path, icon, active:, external: false)
    classes = "flex items-center gap-3 h-12 px-4 rounded-button text-lg " +
      (active ? "bg-bg font-bold text-text shadow-inset" : "text-text-sub hover:text-text")
    options = { class: classes, aria: { current: (active ? "page" : nil) } }
    if external
      options[:target] = "_blank"
      options[:rel] = "noopener"
    end
    link_to path, options do
      safe_join([ console_icon(icon), tag.span(label) ])
    end
  end

  ICONS = {
    users: '<path d="M16 19v-1a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v1"/><circle cx="9" cy="7" r="4"/><path d="M22 19v-1a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
    scissors: '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M20 4 8.1 15.9M14.5 14.5 20 20M8.1 8.1 12 12"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M17 8l-5-5-5 5M12 3v12"/>',
    printer: '<path d="M6 9V2h12v7"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    check: '<path d="M20 6 9 17l-5-5"/>',
    minus: '<path d="M5 12h14"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="3"/><path d="M8 2v4M16 2v4M3 10h18"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1L7 17M17 7l2.1-2.1"/>',
    car: '<path d="M5 17h14M6 17l1.5-6.5A2 2 0 0 1 9.4 9h5.2a2 2 0 0 1 1.9 1.5L18 17"/><circle cx="7.5" cy="17.5" r="1.8"/><circle cx="16.5" cy="17.5" r="1.8"/>',
    bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    mail: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 6L2 7"/>',
    shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/><path d="m9 12 2 2 4-4"/>',
    devices: '<rect x="2" y="4" width="14" height="11" rx="2"/><path d="M8 19h2M18 9h2a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-2"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
    map: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M9 22V12"/><path d="M9 12l-6-4.5"/><path d="M9 12l6-4.5"/>'
  }.freeze

  def console_icon(name, size: 20)
    tag.svg(ICONS.fetch(name).html_safe, xmlns: "http://www.w3.org/2000/svg", width: size, height: size, viewBox: "0 0 24 24",
            fill: "none", stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round", aria: { hidden: true })
  end
end
