class GmailConnectionsController < ApplicationController
  before_action :set_connection
  rescue_from Gmail::Error, with: :connection_error

  def show
    @reviews = @connection.gmail_review_items.where(resolved: false).order(:created_at)
  end

  def update
    @connection.with_lock do
      settings = params.require(:gmail_connection).permit(:client_id, :client_secret, :shopify_senders, :import_since, :poll_interval_seconds).to_h
      settings.delete(:client_secret) if settings[:client_secret].blank?
      changed_credentials = settings.any? { |key, value| %w[client_id client_secret].include?(key) && @connection.public_send(key) != value }
      reset_history = settings.any? { |key, value| %w[import_since shopify_senders].include?(key) && @connection.public_send(key).to_s != value.to_s }
      @connection.assign_attributes(settings)
      @connection.history_id = nil if reset_history
      if changed_credentials
        @connection.assign_attributes(access_token: nil, refresh_token: nil, expires_at: nil, polling_enabled: false,
          sending_enabled: false, alias_confirmed: false, alias_verified_at: nil, status: "needs_authorization",
          authorization_version: @connection.authorization_version + 1)
      end
      @connection.save!
    end
    redirect_to gmail_connection_path, notice: "Gmail settings saved. Secrets are encrypted and never displayed.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to gmail_connection_path, alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  def connect
    state = SecureRandom.hex(32)
    verifier = SecureRandom.urlsafe_base64(48)
    session[:gmail_oauth] = { state: state, verifier: verifier, created_at: Time.current.to_i, version: @connection.authorization_version }
    redirect_to Gmail::Oauth.new(@connection).authorize_url(state: state, verifier: verifier), allow_other_host: true
  end

  def callback
    pending = session.delete(:gmail_oauth)&.stringify_keys
    valid_state = pending && params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(pending["state"], params[:state].to_s)
    raise Gmail::AuthorizationError.new("oauth_state_invalid_or_expired") unless valid_state && pending["created_at"].to_i > 10.minutes.ago.to_i && pending["version"].to_i == @connection.authorization_version
    raise Gmail::AuthorizationError.new("oauth_consent_cancelled") if params[:error].present? || params[:code].blank?
    result = Gmail::Oauth.new(@connection).exchange(code: params[:code], verifier: pending.fetch("verifier"))
    raise Gmail::AuthorizationError.new("required_gmail_permissions_missing") unless (GmailConnection::SCOPES - result.fetch("scope", "").split).empty?
    raise Gmail::AuthorizationError.new("offline_authorization_missing_reconnect") if result["refresh_token"].blank?
    client = Gmail::Client.new(@connection, access_token: result.fetch("access_token"))
    raise Gmail::AuthorizationError.new("wrong_google_account_select_kevin") unless client.profile.fetch("emailAddress").downcase == GmailConnection::MAILBOX
    @connection.with_lock do
      raise Gmail::AuthorizationError.new("oauth_configuration_changed") unless pending["version"].to_i == @connection.authorization_version
      @connection.update!(access_token: result.fetch("access_token"), refresh_token: result.fetch("refresh_token"),
        expires_at: result.fetch("expires_in", 3600).to_i.seconds.from_now, authorization_version: @connection.authorization_version + 1,
        status: "connected", last_error: nil, polling_enabled: true, sending_enabled: false, alias_confirmed: false, alias_verified_at: nil)
    end
    GmailSyncJob.perform_later(@connection.id, force: true)
    redirect_to gmail_connection_path, notice: "Gmail connected. Reading is enabled; live sending remains off.", status: :see_other
  end

  def sync
    raise Gmail::AuthorizationError.new("connect_gmail_first") unless @connection.authorized?
    GmailSyncJob.perform_later(@connection.id, force: true)
    redirect_to gmail_connection_path, notice: "Synchronization requested. Refresh to see the result.", status: :see_other
  end

  def enable_sending
    raise Gmail::Error.new("confirm_sales_alias_in_gmail_first") unless params[:alias_confirmed] == "1"
    result = Gmail::Client.new(@connection).alias_settings
    raise Gmail::Error.new("sales_alias_not_accepted") unless result["sendAsEmail"] == GmailConnection::SALES_ADDRESS && result["verificationStatus"] == "accepted"
    @connection.update!(alias_confirmed: true, alias_verified_at: Time.current, sending_enabled: true)
    redirect_to gmail_connection_path, notice: "Sales alias verified. Every live email still requires exact approval and explicit confirmation.", status: :see_other
  end

  def disable_sending
    @connection.update!(sending_enabled: false)
    redirect_to gmail_connection_path, notice: "Live sending disabled.", status: :see_other
  end

  def disconnect
    @connection.with_lock do
      @connection.update!(status: "disabled", access_token: nil, refresh_token: nil, expires_at: nil,
        polling_enabled: false, sending_enabled: false, alias_confirmed: false, alias_verified_at: nil,
        authorization_version: @connection.authorization_version + 1)
    end
    redirect_to gmail_connection_path, notice: "Gmail disconnected locally. You can also revoke the app in your Google account.", status: :see_other
  end

  private

  def set_connection
    @connection = GmailConnection.configured
  end

  def connection_error(error)
    @connection.failure!(error) unless error.code.start_with?("oauth_state", "oauth_consent")
    redirect_to gmail_connection_path, alert: "Gmail: #{error.code.humanize}. See setup instructions or reconnect.", status: :see_other
  end
end
