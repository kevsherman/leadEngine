require "mail"

module Gmail
  class Envelope
    attr_reader :data
    def initialize(data)
      @data = data
      @headers = Array(data.dig("payload", "headers")).to_h { |item| [ item.fetch("name").downcase, item.fetch("value") ] }
    end

    def header(name)
      @headers[name.downcase].to_s
    end

    def addresses(name)
      Mail::AddressList.new(header(name)).addresses.map { |item| item.address.downcase }.uniq
    rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
      []
    end

    def sender
      addresses("From").first.to_s
    end

    def recipients
      (addresses("To") + addresses("Cc") + addresses("Delivered-To")).uniq
    end

    def subject
      Mail::Encodings.value_decode(header("Subject")).presence || "(No subject)"
    end

    def message_id
      header("Message-ID").scan(/<[^<>\s]+>/).first
    end

    def reference_ids
      (header("In-Reply-To") + " " + header("References")).scan(/<[^<>\s]+>/).uniq
    end

    def own_sender?
      [ GmailConnection::MAILBOX, GmailConnection::SALES_ADDRESS ].include?(sender)
    end

    def safe_labels?
      (Array(data["labelIds"]) & %w[SPAM TRASH DRAFT]).empty?
    end

    def sales_addressed?
      recipients.include?(GmailConnection::SALES_ADDRESS)
    end

    def form_candidate?(connection)
      connection.sender_addresses.include?(sender) &&
        (recipients & [ GmailConnection::MAILBOX, GmailConnection::SALES_ADDRESS ]).any? &&
        subject.match?(/new customer message|contact form|nouveau message client/i)
    end
  end
end
