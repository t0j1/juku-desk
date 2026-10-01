module PdfSplitter
  class PrintOptimizer
    # 問題と解答などを1つのPDFにまとめる
    def self.bundle(outputs)
      pdf = CombinePDF.new
      outputs.each { |o| pdf << CombinePDF.parse(Builder.build(o)) }
      pdf.to_pdf
    end
  end
end
