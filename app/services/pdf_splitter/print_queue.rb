require "open3"

module PdfSplitter
  # 印刷リスト（回 × 問題/解答/両方）を1つのPDFにする。
  # 分割済みファイルをつなげるのではなく、原本のページ範囲を qpdf で1回だけ切り出す（メモリを使わない）
  class PrintQueue
    KINDS = { "problem" => %w[problem], "answer" => %w[answer], "both" => %w[problem answer] }.freeze
    KIND_LABELS = { "problem" => "問題のみ", "answer" => "解答のみ", "both" => "問題と解答" }.freeze
    Item = Struct.new(:round, :kind, keyword_init: true)

    attr_reader :errors, :items

    # raw は ["第1回:both", "第2回:problem"] の形
    def initialize(job, raw, pad_even: false)
      @job = job
      @pad_even = pad_even
      @errors = []
      @items = Array(raw).filter_map do |s|
        round, kind = s.to_s.split(":", 2)
        Item.new(round:, kind:) if round.present? && KINDS.key?(kind)
      end
    end

    def self.max_rounds = PdfSplitter.config.dig(:limits, :max_print_rounds).to_i

    def ranges
      outputs = @job.outputs.to_a
      @items.flat_map do |it|
        KINDS[it.kind].filter_map do |k|
          outputs.find { |o| o.round_label == it.round && o.section_kind == k }
        end
      end.map { |o| [ o.page_from, o.page_to ] }
    end

    def valid?
      @errors = []
      @errors << "印刷する回を選んでください。" if @items.empty?
      max = self.class.max_rounds
      @errors << "まとめて印刷できるのは#{max}回分までです。" if @items.map(&:round).uniq.size > max
      @errors << "選んだ回のファイルが見つかりません。" if @items.any? && ranges.empty?
      @errors.empty?
    end

    def filename
      label = @items.map { |it| "#{it.round}#{KIND_LABELS[it.kind]}" }.join("_")
      "#{label.truncate(80, omission: '')}.pdf"
    end

    def to_pdf
      @job.with_original_file do |src|
        Dir.mktmpdir do |dir|
          blank = File.join(dir, "blank.pdf")
          File.binwrite(blank, self.class.blank_pdf) if @pad_even
          args = ranges.flat_map do |from, to|
            pages = [ src, "#{Integer(from)}-#{Integer(to)}" ]
            pages += [ blank, "1" ] if @pad_even && (to - from + 1).odd?
            pages
          end
          out = File.join(dir, "out.pdf")
          _o, err, st = Open3.capture3("qpdf", "--empty", "--pages", *args, "--", out)
          raise SplitError, err.presence || "qpdf failed" unless st.success? || st.exitstatus == 3
          File.binread(out)
        end
      end
    end

    # A4 の白紙1ページ
    def self.blank_pdf
      objs = [ "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << >> >>" ]
      body = +"%PDF-1.4\n"
      offsets = objs.each_with_index.map do |o, i|
        off = body.bytesize
        body << "#{i + 1} 0 obj\n#{o}\nendobj\n"
        off
      end
      xref = body.bytesize
      body << "xref\n0 #{objs.size + 1}\n0000000000 65535 f \n"
      offsets.each { |off| body << format("%010d 00000 n \n", off) }
      body << "trailer\n<< /Size #{objs.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    end
  end
end
