catalog = ProviderCatalog::Load.call
puts "Loaded provider catalog with #{catalog.providers.size} providers and #{catalog.model_roles.size} model roles."

installation = Installation.order(:id).first

if installation.present?
  bundled_runtime = Installations::RegisterBundledAgentRuntime.call(installation: installation)

  if bundled_runtime.present?
    puts "Reconciled bundled agent runtime for installation ##{installation.id}."
  else
    puts "Bundled agent runtime is disabled; skipped runtime reconciliation."
  end
else
  puts "No installation present; skipped bundled agent runtime reconciliation."
end
