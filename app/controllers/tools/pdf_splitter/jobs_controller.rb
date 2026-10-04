module Tools
  module PdfSplitter
    class JobsController < BaseController
      # サムネイルは1件ずつ作る（同時に何十MBもの元PDFを読み込んでメモリ不足で落ちるのを防ぐ）
      THUMB_LOCK = Mutex.new

      before_action :set_job, except: %i[ index create ]

      def index
        current_user.pdf_split_jobs.fail_stale!
        @jobs = current_user.pdf_split_jobs.order(created_at: :desc).limit(50)
      end

      def show
        @job.fail_if_stale!
        @boundaries = @job.boundaries.presence || []
      end

      def create
        result = ::PdfSplitter::Uploader.new(current_user).call(params[:file], password: params[:password])
        if result.error
          redirect_to tools_pdf_splitter_jobs_path, alert: result.error
        else
          AuditLog.record!(:create, result.job, metadata: { filename: result.job.original_filename, pages: result.job.page_count })
          ::PdfSplitter::AnalyzeJob.perform_later(result.job.id)
          redirect_to tools_pdf_splitter_job_path(result.job)
        end
      end

      def destroy
        AuditLog.record!(:delete, @job, metadata: { filename: @job.original_filename })
        @job.destroy!
        redirect_to tools_pdf_splitter_jobs_path, notice: "削除しました。", status: :see_other
      end

      # 解析をやり直す
      def analyze
        @job.update!(status: :uploaded, error_message: nil)
        ::PdfSplitter::AnalyzeJob.perform_later(@job.id)
        redirect_to tools_pdf_splitter_job_path(@job)
      end

      # 境界の手動修正（保存のみ）。N等分の適用もここで受ける
      def update_boundaries
        if params[:equal_parts].present?
          @job.update!(boundaries: ::PdfSplitter::PatternGuesser.equal_parts(@job.page_count, params[:equal_parts]), pattern: 4)
          return redirect_to tools_pdf_splitter_job_path(@job), notice: "#{params[:equal_parts].to_i}等分の範囲を入れました。確認して分割してください。"
        end

        save_boundaries
      end

      # 境界を確定して出力を作る（自動判定は提案まで。確定は人がこのボタンで行う）
      def split
        # 「範囲だけ保存」は分割フォームの中のボタン。Rails 8.1 はフォームごとの CSRF トークンなので、
        # formaction で別のURLに送ると 422 になる。同じURLで受けて保存だけ行う
        return save_boundaries if params.key?(:save_only)

        set = ::PdfSplitter::BoundarySet.new((params.key?(:boundaries) || params.key?(:pairs)) ? boundary_rows : @job.boundaries, page_count: @job.page_count)
        return render_invalid(set) unless set.valid?

        names = ::PdfSplitter::Namer.new.then do |namer|
          generated = set.to_a.each_with_index.map { |b, i| b["name"] ? namer.sanitize(b["name"]) : namer.build(b, index: i + 1) }
          ::PdfSplitter::Namer.uniquify(generated)
        end

        PdfSplitJob.transaction do
          @job.outputs.destroy_all
          set.to_a.each_with_index do |b, i|
            @job.outputs.create!(display_name: names[i], page_from: b["from"], page_to: b["to"],
                                 round_label: b["round"], section_kind: b["kind"], position: i)
          end
          @job.update!(boundaries: set.to_a, status: :splitting, output_count: set.to_a.size, error_message: nil)
        end
        ::PdfSplitter::SplitJob.perform_later(@job.id)
        redirect_to tools_pdf_splitter_job_path(@job), notice: "#{set.to_a.size}ファイルに分割しています。"
      end

      # ファイル名の一括変更（個別編集・先頭/末尾への一括追加）
      def update_names
        namer = ::PdfSplitter::Namer.new
        outputs = @job.outputs.to_a
        edited = params.fetch(:names, {})
        names = outputs.map do |o|
          n = edited[o.id.to_s].presence || o.display_name
          namer.sanitize("#{params[:prefix]}#{n}#{params[:suffix]}")
        end
        names = ::PdfSplitter::Namer.uniquify(names)
        PdfSplitOutput.transaction do
          outputs.zip(names).each { |o, n| o.update!(display_name: n) if o.display_name != n }
        end
        redirect_to tools_pdf_splitter_job_path(@job), notice: "ファイル名を更新しました。"
      end

      # 印刷ページ（iPad で QR から開く）
      def print
        @outputs = @job.outputs.to_a
        @bundles = @outputs.select(&:round_label).group_by(&:round_label).select { |_, os| os.size > 1 }
        @rounds = @outputs.select(&:round_label).group_by(&:round_label)
      end

      # 印刷リスト（回ごとに 問題/解答/両方）を1つのPDFにして開く
      def print_queue
        queue = ::PdfSplitter::PrintQueue.new(@job, params[:items], pad_even: params[:pad_even] == "1")
        return redirect_to(print_tools_pdf_splitter_job_path(@job), alert: queue.errors.join(" ")) unless queue.valid?
        AuditLog.record!(:print, @job, metadata: { job_id: @job.id, queue: params[:items], pad_even: params[:pad_even] == "1" })
        queue.with_pdf { |path| send_pdf_file(path, filename: queue.filename, disposition: "inline") }
      end

      # 同じ回の問題＋解答を1つにまとめて印刷（inline）
      def print_bundle
        outputs = @job.outputs.where(round_label: params[:round]).to_a
        return redirect_to(print_tools_pdf_splitter_job_path(@job), alert: "対象のファイルがありません。") if outputs.empty?
        AuditLog.record!(:print, @job, metadata: { job_id: @job.id, bundle: params[:round], outputs: outputs.map(&:display_name) })
        ::PdfSplitter::PrintOptimizer.with_bundle(outputs) { |path| send_pdf_file(path, filename: "#{params[:round]}_まとめ.pdf", disposition: "inline") }
      end

      def download_zip
        outputs = @job.outputs.to_a
        return redirect_to(tools_pdf_splitter_job_path(@job), alert: "分割済みのファイルがありません。") if outputs.empty?
        AuditLog.record!(:export, @job, metadata: { job_id: @job.id, format: "zip", count: outputs.size })
        ::PdfSplitter::Zipper.with_zip(outputs) do |path|
          send_pdf_file(path, filename: "#{File.basename(@job.original_filename, '.*')}.zip", type: "application/zip", disposition: "attachment")
        end
      end

      # 境界確認用のサムネイル（保存しない）
      def thumbnail
        page = params[:page].to_i
        return head(:not_found) unless page.between?(1, @job.page_count.to_i)
        png = Rails.cache.fetch([ "pdf_thumb", @job.id, page ], expires_in: 1.day) do
          THUMB_LOCK.synchronize { ::PdfSplitter::Thumbnailer.png_from_path(@job.original_cache_path, page) }
        end
        expires_in 1.hour, public: false
        send_data png, type: "image/png", disposition: "inline"
      rescue ::PdfSplitter::Error => e
        # img のリクエストなので、ページへのリダイレクトではなく 404 を返す（show を何度も描き直さない）
        Rails.logger.warn("thumbnail failed job=#{@job.id} page=#{page}: #{e.message.truncate(200)}")
        head :not_found
      end

      private
        # 入力が誤っていても打ち直さなくて済むよう、エラー時は入力した値のまま画面を出し直す
        def save_boundaries
          set = ::PdfSplitter::BoundarySet.new(boundary_rows, page_count: @job.page_count)
          if set.valid?
            @job.update!(boundaries: set.to_a, pattern: @job.auto_detected? ? @job.pattern : 3)
            redirect_to tools_pdf_splitter_job_path(@job), notice: "分割範囲を保存しました。"
          else
            render_invalid(set)
          end
        end

        def render_invalid(set)
          @boundaries = boundary_rows.map { |r| (r.respond_to?(:to_h) ? r.to_h : r).stringify_keys }
          flash.now[:alert] = set.errors.join(" ")
          render :show, status: :unprocessable_entity
        end

        def boundary_rows
          if params.key?(:pairs)
            pairs = params.fetch(:pairs, []).map { |r| r.permit(:round, :problem_from, :problem_to, :answer_from, :answer_to) }
            return ::PdfSplitter::PairRows.expand(pairs)
          end
          params.fetch(:boundaries, []).map { |r| r.permit(:from, :to, :round, :kind, :name) }
        end
    end
  end
end
