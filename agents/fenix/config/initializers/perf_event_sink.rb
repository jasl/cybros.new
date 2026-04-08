Rails.application.config.after_initialize do
  Perf::EventSink.install!(source_app: "fenix")
end
