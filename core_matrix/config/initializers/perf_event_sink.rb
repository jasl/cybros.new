Rails.application.config.after_initialize do
  Perf::EventSink.install!(source_app: "core_matrix")
end
