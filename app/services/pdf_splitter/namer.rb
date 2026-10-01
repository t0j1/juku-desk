module PdfSplitter
  class Namer
    FORBIDDEN = %r{[/\\:*?"<>|\x00-\x1f]}
    RESERVED  = /\A(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])\z/i

    def initialize(config = PdfSplitter.config[:naming])
      @c = config.with_indifferent_access
    end

    # boundary = { "round" => "第1回", "kind" => "problem" }
    def build(boundary, index:)
      round = boundary["round"].presence || @c[:round_fallback].gsub("{index}", index.to_s)
      round = zero_pad(round) if @c[:zero_pad]
      kind  = @c[:kind_labels][boundary["kind"].presence || "unknown"] || @c[:kind_labels][:unknown]

      name = @c[:template]
             .gsub("{prefix}", @c[:prefix].to_s)
             .gsub("{suffix}", @c[:suffix].to_s)
             .gsub("{round}", round.to_s)
             .gsub("{round_num}", round[/\d+/].to_s)
             .gsub("{kind}", kind.to_s)
             .gsub("{date}", Date.current.strftime("%Y%m%d"))
             .gsub("{instructor}", boundary["instructor"].to_s)

      sanitize(name)
    end

    def build_all(boundaries)
      self.class.uniquify(boundaries.each_with_index.map { |b, i| build(b, index: i + 1) })
    end

    def sanitize(name)
      s = name.to_s.gsub(FORBIDDEN, "_").gsub(/\s+/, " ").strip
      s = s.sub(/\.pdf\z/i, "")
      s = s.sub(/\A[.\s]+/, "").sub(/[.\s]+\z/, "")
      s = "無題" if s.blank?
      s = "_#{s}" if s.match?(RESERVED)
      truncate_bytes(s, @c[:max_bytes].to_i)
    end

    def self.uniquify(names)
      seen = Hash.new(0)
      names.map { |n| seen[n] += 1; seen[n] == 1 ? n : "#{n}_#{seen[n]}" }
    end

    private
      # 日本語は1文字3バイト。バイト数で切る
      def truncate_bytes(str, max)
        return str if max <= 0 || str.bytesize <= max
        out = +""
        str.each_char do |ch|
          break if (out.bytesize + ch.bytesize) > max
          out << ch
        end
        out
      end

      def zero_pad(round) = round.sub(/(\d+)/) { format("%02d", $1.to_i) }
  end
end
