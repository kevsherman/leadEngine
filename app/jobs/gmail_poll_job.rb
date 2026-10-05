class GmailPollJob < ApplicationJob
  def perform
    GmailConnection.where(polling_enabled: true, status: %w[connected error]).find_each do |connection|
      GmailSyncJob.perform_later(connection.id)
    end
  end
end
