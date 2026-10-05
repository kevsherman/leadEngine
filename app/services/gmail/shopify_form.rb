module Gmail
  class ShopifyForm
    # Parse only configured notification senders with recognizable form subjects.
    # The notification sender is never assumed to be the customer.
    def self.parse(body, envelope)
      values = {}
      current = nil
      body.each_line do |line|
        if (match = line.match(/^\s*(Name|Email|E-mail|Phone|Phone Number|Body|Message|Country Code|Nom|Courriel|Téléphone)\s*:\s*(.*)$/i))
          key = match[1].downcase
          current = case key
          when "email", "e-mail", "courriel" then :email
          when "name", "nom" then :name
          when "body", "message" then :body
          when "phone", "phone number", "téléphone" then :phone
          else :country
          end
          values[current] = match[2].strip
        elsif current
          values[current] += "
#{line.strip}"
        end
      end
      email = values[:email].to_s.strip.downcase
      return nil unless URI::MailTo::EMAIL_REGEXP.match?(email) && values[:body].present?
      reply_addresses = envelope.addresses("Reply-To")
      return nil if reply_addresses.any? && !reply_addresses.include?(email)
      { email: email, name: values[:name].presence || email, body: values[:body].strip,
        fields: { "contact_email" => email, "phone" => values[:phone].presence }.compact }
    end
  end
end
