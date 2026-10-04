module PdfSplitter
  class PrintOptimizer
    # 問題と解答などを1つのPDFにまとめる
    def self.bundle(outputs) = with_bundle(outputs) { |path| File.binread(path) }

    # 一時ファイルのパスを渡す（ブロックを抜けると消える）。各出力は一時ファイルから読む
    def self.with_bundle(outputs)
      pdf = CombinePDF.new
      outputs.each { |o| Builder.with_file(o) { |path| pdf << CombinePDF.load(path) } }
      Dir.mktmpdir do |dir|
        out = File.join(dir, "bundle.pdf")
        pdf.save(out)
        yield out
      end
    end
  end
end
