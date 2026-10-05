class GmailSyncJob < ApplicationJob
  def perform(connection_id, force: false)
    Gmail::Synchronizer.new(GmailConnection.find(connection_id)).call(force: force)
  end
end
