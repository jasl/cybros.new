catalog = ProviderCatalog::Registry.current
puts "Loaded provider catalog with #{catalog.providers.size} providers and #{catalog.model_roles.size} model roles."

seed_secret = lambda do |env_key|
  ENV[env_key].to_s.strip.presence
end

provider_visible_in_env = lambda do |provider_handle|
  provider = catalog.provider(provider_handle)
  provider.fetch(:enabled) && provider.fetch(:environments).include?(Rails.env)
end

ensure_provider_policy = lambda do |installation, provider_handle|
  next if ProviderPolicy.exists?(installation: installation, provider_handle: provider_handle)

  ProviderPolicies::Upsert.call(
    installation: installation,
    actor: nil,
    provider_handle: provider_handle,
    enabled: true,
    selection_defaults: {}
  )
end

ensure_provider_entitlement = lambda do |installation, provider_handle|
  next if ProviderEntitlement.where(installation: installation, provider_handle: provider_handle).exists?

  ProviderEntitlements::Upsert.call(
    installation: installation,
    actor: nil,
    provider_handle: provider_handle,
    entitlement_key: "shared_window",
    window_kind: "rolling_five_hours",
    quota_limit: 200_000,
    active: true,
    metadata: {}
  )
end

ensure_provider_credential = lambda do |installation, provider_handle, credential_kind, secret|
  credential = ProviderCredential.find_by(
    installation: installation,
    provider_handle: provider_handle,
    credential_kind: credential_kind
  )

  next if credential.present? && credential.secret == secret && credential.metadata == {}

  ProviderCredentials::UpsertSecret.call(
    installation: installation,
    actor: nil,
    provider_handle: provider_handle,
    credential_kind: credential_kind,
    secret: secret,
    metadata: {}
  )
end

installation = Installation.order(:id).first

if installation.present?
  bundled_runtime = Installations::RegisterBundledAgentRuntime.call(installation: installation)

  if bundled_runtime.present?
    puts "Reconciled bundled agent runtime for installation ##{installation.id}."
  else
    puts "Bundled agent runtime is disabled; skipped runtime reconciliation."
  end

  if provider_visible_in_env.call("dev")
    ensure_provider_policy.call(installation, "dev")
    ensure_provider_entitlement.call(installation, "dev")
  end

  {
    "openai" => seed_secret.call("OPENAI_API_KEY"),
    "openrouter" => seed_secret.call("OPENROUTER_API_KEY"),
  }.each do |provider_handle, secret|
    next if secret.blank?
    next unless provider_visible_in_env.call(provider_handle)

    provider = catalog.provider(provider_handle)
    ensure_provider_credential.call(installation, provider_handle, provider.fetch(:credential_kind), secret)
    ensure_provider_policy.call(installation, provider_handle)
    ensure_provider_entitlement.call(installation, provider_handle)
  end
else
  puts "No installation present; skipped bundled agent runtime reconciliation."
end
