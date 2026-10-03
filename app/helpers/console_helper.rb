module ConsoleHelper
  PILL_SYMBOLS = { ok: "●", busy: "◐", ng: "✕", neutral: "○" }.freeze

  # Status pill: meaning is carried by symbol + text, not color alone.
  def status_pill(label, kind)
    tag.span(class: "pill pill-#{kind}") do
      safe_join([ tag.span(PILL_SYMBOLS.fetch(kind), aria: { hidden: true }), label ])
    end
  end

  def pdf_job_pill_kind(job)
    return :ok if job.done?
    return :ng if job.failed?
    return :busy if job.analyzing? || job.splitting? || job.uploaded?
    :neutral
  end

  def nav_item(label, path, icon, active:)
    classes = "flex items-center gap-3 h-12 px-4 rounded-xl text-[15px] " +
      (active ? "bg-white font-bold text-ink shadow-card" : "text-ink-sub hover:bg-white/60")
    link_to path, class: classes, aria: { current: (active ? "page" : nil) } do
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
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>'
  }.freeze

  def console_icon(name, size: 20)
    tag.svg(ICONS.fetch(name).html_safe, xmlns: "http://www.w3.org/2000/svg", width: size, height: size, viewBox: "0 0 24 24",
            fill: "none", stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round", aria: { hidden: true })
  end
end
