module Gmail
  class Synchronizer
    def initialize(connection, client: Client.new(connection))
      @connection, @client = connection, client
    end

    def call(force: false)
      ActiveRecord::Base.connection_pool.with_connection do |database|
        lock_key = 7_241_100 + @connection.id
        return unless database.select_value("SELECT pg_try_advisory_lock(#{Integer(lock_key)})")
        begin
          @connection.reload
          return unless @connection.authorized? && @connection.polling_enabled?
          return unless force || @connection.last_attempt_at.nil? || @connection.last_attempt_at <= @connection.poll_interval_seconds.seconds.ago
          @connection.update!(last_attempt_at: Time.current)
          @version = @connection.authorization_version
          @importer = Importer.new(@connection, client: @client)
          if @connection.history_id.present?
            incremental
          else
            bootstrap
          end
          @connection.reload
          return unless @connection.authorization_version == @version && @connection.polling_enabled?
          @connection.update!(status: "connected", last_error: nil, last_synced_at: Time.current)
        rescue Error => error
          @connection.reload
          @connection.failure!(error) if @connection.authorization_version == @version
        ensure
          database.execute("SELECT pg_advisory_unlock(#{Integer(lock_key)})")
        end
      end
    end

    private

    def bootstrap
      cursor = @client.profile.fetch("historyId") # Capture BEFORE listing, so concurrent arrivals are recovered.
      page = nil
      query = "after:#{@connection.import_since.strftime('%Y/%m/%d')} {to:#{GmailConnection::SALES_ADDRESS} cc:#{GmailConnection::SALES_ADDRESS} deliveredto:#{GmailConnection::SALES_ADDRESS} from:#{GmailConnection::SALES_ADDRESS} #{@connection.sender_addresses.map { |sender| "from:#{sender}" }.join(' ')}}"
      loop do
        result = @client.list_messages(query: query, page_token: page)
        Array(result["messages"]).reverse_each { |item| import(item.fetch("id")) }
        page = result["nextPageToken"]
        break unless page
      end
      # Known threads also recover direct-to-Kevin replies and messages sent as Kevin.
      Conversation.where(gmail_connection: @connection).distinct.pluck(:gmail_thread_id).compact.each do |thread|
        @client.thread(thread).fetch("messages", []).each { |item| import(item.fetch("id")) }
      rescue NotFound
        next
      end
      # Recover a customer reply that started a new Gmail thread during an expired-cursor gap.
      Conversation.where(gmail_connection: @connection).distinct.pluck(:customer_email).each do |email|
        page = nil
        loop do
          result = @client.list_messages(query: "after:#{@connection.import_since.strftime('%Y/%m/%d')} {from:#{email} to:#{email}}", page_token: page)
          Array(result["messages"]).reverse_each { |item| import(item.fetch("id")) }
          page = result["nextPageToken"]
          break unless page
        end
      end
      checkpoint(cursor)
    end

    def incremental
      page = nil
      cursor = @connection.history_id
      loop do
        result = @client.history(start_id: @connection.history_id, page_token: page)
        Array(result["history"]).each do |event|
          Array(event["messagesAdded"]).each { |item| import(item.fetch("message").fetch("id")) }
        end
        cursor = result.fetch("historyId", cursor)
        page = result["nextPageToken"]
        break unless page
      end
      checkpoint(cursor)
    rescue NotFound
      bootstrap # Expired history IDs require a filtered full sync; imports remain idempotent.
    end

    def import(id)
      @connection.reload
      raise AuthorizationError.new("connection_changed_during_sync") unless @connection.authorization_version == @version && @connection.polling_enabled?
      @importer.import_id(id)
    end

    def checkpoint(cursor)
      @connection.with_lock do
        raise AuthorizationError.new("connection_changed_during_sync") unless @connection.authorization_version == @version && @connection.polling_enabled?
        @connection.update!(history_id: cursor)
      end
    end
  end
end
