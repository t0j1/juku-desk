require "zip"

module PdfSplitter
  class Zipper
    def self.zip(outputs)
      io = Zip::OutputStream.write_buffer do |zos|
        outputs.each do |o|
          zos.put_next_entry(o.filename)
          zos.write(Builder.build(o))
        end
      end
      io.string
    end
  end
end
