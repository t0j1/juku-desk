# Solid Queue のワーカー（解析・分割・Gemini 呼び出し）は、CPU の優先度を最低にする。
# 本番は SOLID_QUEUE_IN_PUMA で同じコンテナに Puma がいるので、重いジョブが CPU を使い切ると
# /up（Render のヘルスチェック・5秒）に返せず、再起動される。ワーカーとして fork されたプロセスだけを下げる
Rails.application.config.after_initialize do
  next unless defined?(SolidQueue) && SolidQueue.respond_to?(:on_worker_start)

  SolidQueue.on_worker_start do
    PdfSplitter.lower_priority!
  rescue SystemCallError => e
    Rails.logger.warn("could not lower worker priority: #{e.message}")
  end
end
