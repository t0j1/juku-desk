# PDF を丸ごと String にせず、ファイルから少しずつ流して返す。
# 一時ファイルはブロックを抜けると消えるが、開いたハンドルから読み続けられる（POSIX）。
module PdfStreaming
  extend ActiveSupport::Concern

  CHUNK_BYTES = 64.kilobytes

  private
    def send_output_pdf(output, disposition:)
      ::PdfSplitter::Builder.with_file(output) { |path| send_pdf_file(path, filename: output.filename, disposition:) }
    end

    def send_pdf_file(path, filename:, disposition:, type: "application/pdf")
      io = File.open(path, "rb")
      send_file_headers!(type:, filename:, disposition:)
      response.headers["Content-Length"] = io.size.to_s
      self.response_body = Enumerator.new do |chunks|
        while (chunk = io.read(CHUNK_BYTES))
          chunks << chunk
        end
      ensure
        io.close
      end
    end
end
