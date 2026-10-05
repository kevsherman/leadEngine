require "json"

keys = if Rails.env.test?
  %w[primary_key deterministic_key key_derivation_salt].to_h { |name| [ name, "test-only-#{name}".ljust(64, "0") ] }
elsif Rails.root.join(".local/gmail-encryption.json").exist? && !Rails.env.production?
  JSON.parse(Rails.root.join(".local/gmail-encryption.json").read)
else
  %w[primary_key deterministic_key key_derivation_salt].to_h { |name| [ name, ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"] ] }
end
# No plaintext fallback. Setup generates local keys before Rails boots.
keys.each do |name, value|
  Rails.application.config.active_record.encryption.public_send("#{name}=", value) if value.present?
end
