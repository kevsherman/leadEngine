# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

Rails.application.config.filter_parameters += %i[body payload to cc customer_email]

Rails.application.config.filter_parameters += %i[code state access_token refresh_token client_secret client_id code_verifier raw references_header]

Rails.application.config.filter_redirect += [ "accounts.google.com", "oauth2.googleapis.com" ]
