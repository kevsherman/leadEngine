require "base64"
require "nokogiri"

module Gmail
  class Content
    def self.read(payload)
      parts = flatten(payload)
      text = parts.select { |part| part["mimeType"] == "text/plain" && part["filename"].blank? }
      text = parts.select { |part| part["mimeType"] == "text/html" && part["filename"].blank? } if text.empty?
      body = text.filter_map do |part|
        encoded = part.dig("body", "data")
        next unless encoded
        decoded = Base64.urlsafe_decode64(encoded).force_encoding("UTF-8").scrub
        if part["mimeType"] == "text/html"
          fragment = Nokogiri::HTML.fragment(decoded)
          fragment.css("script, style").remove
          fragment.css("br").each { |node| node.replace("
") }
          fragment.css("p, div, tr").each { |node| node.add_next_sibling(Nokogiri::XML::Text.new("
", fragment.document)) }
          decoded = fragment.text
        end
        decoded
      end.join("
").strip
      raise MalformedMessage.new("message_too_large_for_import") if body.bytesize > 500_000
      body.presence || "[No inline message text. Review any attachments in Gmail.]"
    rescue ArgumentError
      raise MalformedMessage.new("invalid_message_encoding")
    end

    def self.attachments(payload)
      flatten(payload).select { |part| part["filename"].present? }.map do |part|
        { filename: part["filename"], mime_type: part["mimeType"], size: part.dig("body", "size"), provider_attachment_id: part.dig("body", "attachmentId") }
      end
    end

    def self.flatten(payload, depth = 0)
      raise MalformedMessage.new("invalid_message_structure") if depth > 20
      [ payload ] + Array(payload["parts"]).flat_map { |part| flatten(part, depth + 1) }
    end
  end
end
