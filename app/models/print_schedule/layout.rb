# 定例印刷の帳票（名簿・単語テスト）のレイアウト調整値。未指定の項目は既定案で補い、範囲を外れた値は検証で止める。
# layout_config（jsonb）には変えた項目だけを入れればよい。
class PrintSchedule < ApplicationRecord
  module Layout
    PAPERS = %w[ A4 B5 B4 ].freeze
    ORIENTATIONS = %w[ portrait landscape ].freeze
    PAGE_NUMBERS = %w[ none right center ].freeze
    ROW_MODES = %w[ auto manual ].freeze

    # 項目 => [既定, 型, 範囲または選択肢, ラベル]
    COMMON = {
      "paper" => [ "A4", :choice, PAPERS, "用紙" ],
      "orientation" => [ "portrait", :choice, ORIENTATIONS, "向き" ],
      "margin_v" => [ 15, :int, 5..30, "余白（上下）mm" ],
      "margin_h" => [ 15, :int, 5..30, "余白（左右）mm" ],
      "body_size" => [ 11, :int, 9..16, "本文の文字サイズ pt" ],
      "heading_size" => [ 16, :int, 12..24, "見出しの文字サイズ pt" ],
      "show_date" => [ true, :bool, nil, "見出しに日付を出す" ],
      "page_number" => [ "right", :choice, PAGE_NUMBERS, "ページ番号" ],
      "rules" => [ true, :bool, nil, "罫線" ]
    }.freeze
    ROSTER = {
      "columns" => [ 1, :int, 1..2, "段組み" ],
      "rows_mode" => [ "auto", :choice, ROW_MODES, "1ページの行数" ],
      "rows_per_page" => [ 25, :int, 10..40, "1ページの行数（手動）" ],
      "grade_heading" => [ true, :bool, nil, "学年見出し" ],
      "attendance_width" => [ 20, :int, 12..30, "出欠記入欄の幅 mm" ],
      "furigana" => [ false, :bool, nil, "ふりがな欄" ]
    }.freeze
    WORD_TEST = {
      "columns" => [ 2, :int, 1..2, "段組み" ],
      "answer_rules" => [ true, :bool, nil, "解答欄の罫線" ],
      "show_numbers" => [ true, :bool, nil, "問題番号を出す" ],
      "name_field" => [ true, :bool, nil, "氏名欄" ]
    }.freeze

    SPECS = { "roster" => COMMON.merge(ROSTER), "word_test" => COMMON.merge(WORD_TEST) }.freeze

    module_function

    def spec_for(kind) = SPECS.fetch(kind.to_s, {})

    def defaults(kind) = spec_for(kind).transform_values(&:first)

    # 保存値（文字列でも可）を型に直して、既定で補う。範囲外・選択肢外・型違いは [値, エラー] の errors に入れる
    def resolve(kind, config)
      config = (config || {}).to_h.stringify_keys
      errors = []
      values = spec_for(kind).to_h do |key, (default, type, allowed, label)|
        raw = config.key?(key) ? config[key] : default
        value = coerce(raw, type)
        ok = case type
        when :int then value.is_a?(Integer) && allowed.cover?(value)
        when :choice then allowed.include?(value)
        else [ true, false ].include?(value)
        end
        errors << "#{label}の値が正しくありません" unless ok
        [ key, ok ? value : default ]
      end
      [ values, errors ]
    end

    # フォームから来た文字列を、保存する形（型つき・変えた項目だけ）にする
    def normalize(kind, params)
      params = (params || {}).to_h.stringify_keys
      spec_for(kind).each_with_object({}) do |(key, (default, type, _allowed, _label)), out|
        next unless params.key?(key)
        value = coerce(params[key], type)
        out[key] = value unless value == default
      end
    end

    # 「A4 縦・余白15mm・本文11pt」のような 1 行の要約
    def summary(kind, config)
      v, = resolve(kind, config)
      "#{v["paper"]} #{v["orientation"] == "portrait" ? "縦" : "横"}・余白#{v["margin_v"] == v["margin_h"] ? v["margin_v"] : "#{v["margin_v"]}/#{v["margin_h"]}"}mm・本文#{v["body_size"]}pt"
    end

    def coerce(raw, type)
      case type
      when :int then Integer(raw.to_s, 10) rescue raw
      when :bool then raw.is_a?(String) ? { "1" => true, "true" => true, "0" => false, "false" => false }.fetch(raw, raw) : raw
      else raw.to_s
      end
    end
  end
end
