module PdfSplitter
  # 画面から受け取った境界を検証して正規化する
  class BoundarySet
    attr_reader :errors

    def initialize(rows, page_count:)
      @rows = Array(rows)
      @page_count = page_count.to_i
      @errors = []
    end

    def to_a
      @to_a ||= @rows.filter_map do |r|
        r = r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r.to_h
        r = r.stringify_keys
        next if r["from"].blank? && r["to"].blank?
        { "from" => r["from"].to_i, "to" => r["to"].to_i,
          "round" => r["round"].to_s.strip.presence, "kind" => (%w[problem answer].include?(r["kind"]) ? r["kind"] : nil),
          "name" => r["name"].to_s.strip.presence }
      end
    end

    def valid?
      @errors = []
      @errors << "分割範囲を1つ以上指定してください。" if to_a.empty?
      max = PdfSplitter.config.dig(:limits, :max_outputs).to_i
      @errors << "分割数が多すぎます（上限 #{max}）。" if to_a.size > max
      to_a.each_with_index do |b, i|
        unless b["from"].between?(1, @page_count) && b["to"].between?(b["from"], @page_count)
          @errors << "#{i + 1}行目のページ範囲が正しくありません（1〜#{@page_count}）。"
        end
      end
      @errors.empty?
    end
  end
end
