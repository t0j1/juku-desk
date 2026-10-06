module PrintJobsHelper
  STAPLES = [ "なし", "左上" ].freeze
  DUPLEXES = [ [ "指定なし（ドライバーの設定）", "" ], [ "長辺とじ", "long" ], [ "短辺とじ", "short" ] ].freeze

  def duplex_label(value) = DUPLEXES.find { |_, v| v == value.to_s }&.first&.sub(/（.*/, "")

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
  # ドライバー設定名のプルダウン。一覧（DriverPreset）＋ 一覧に無い現在の値 ＋ 末尾に「新しく追加する」（選ぶと入力欄が出る）。
  # scope: フォームのスコープ名（params のキー）、selected: 現在の値、blank_label: 空にできる画面の先頭の項目（空なら出さない）
  def driver_preset_select(scope, selected: nil, blank_label: nil, field: :driver_preset, input_class: "input mt-1")
    selected = selected.to_s
    names = DriverPreset.listed.pluck(:name)
    options = []
    options << [ blank_label, "" ] if blank_label
    options.concat(names.map { |n| [ n, n ] })
    options << [ "#{selected}（現在の値）", selected ] if selected.present? && names.exclude?(selected)
    options << [ "新しく追加する…", DriverPreset::NEW ]
    selected = names.first.to_s if selected.blank? && blank_label.nil?
    tag.span(data: { controller: "preset-select" }, class: "inline-flex flex-wrap items-center gap-2") do
      select_tag("#{scope}[#{field}]", options_for_select(options, selected), class: "#{input_class} !w-auto", "aria-label": "ドライバーの設定名", data: { preset_select_target: "select", action: "preset-select#toggle" }) +
        text_field_tag("#{scope}[#{field}_new]", nil, maxlength: DriverPreset::NAME_MAX, placeholder: "新しい設定名", hidden: true, class: "#{input_class} !w-56", "aria-label": "新しいドライバー設定名", data: { preset_select_target: "input" })
    end
  end
end
