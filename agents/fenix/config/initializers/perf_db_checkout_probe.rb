Rails.application.config.after_initialize do
  Perf::DbCheckoutProbe.install!
end
