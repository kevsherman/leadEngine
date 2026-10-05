require "net/http"
require "json"

module Gmail
  class Http
    # Fixed Google origins only. No retries for writes, no HTTP debug logging.
    def request(method, url, token: nil, form: nil, json: nil, write: false)
      uri = URI(url)
      raise Error.new("invalid_google_endpoint") unless uri.scheme == "https" && %w[oauth2.googleapis.com gmail.googleapis.com].include?(uri.host)
      request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
      request = request_class.new(uri)
      request["Authorization"] = "Bearer #{token}" if token
      if form
        request.set_form_data(form)
      elsif json
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(json)
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 25
      http.write_timeout = 10
      http.max_retries = 0
      response = http.request(request)
      status = response.code.to_i
      raise AuthorizationError.new("google_authorization_required") if status == 401 || (uri.host == "oauth2.googleapis.com" && status == 400)
      raise NotFound.new("gmail_not_found") if status == 404
      raise UncertainWrite.new("gmail_send_outcome_unknown") if write && status >= 500
      raise Error.new("gmail_http_#{status}") unless (200..299).cover?(status)
      JSON.parse(response.body)
    rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError
      error = write ? UncertainWrite.new("gmail_send_outcome_unknown") : Error.new("google_connection_failed")
      raise error, cause: nil
    rescue JSON::ParserError
      error = write ? UncertainWrite.new("gmail_send_outcome_unknown") : Error.new("invalid_google_response")
      raise error, cause: nil
    end
  end
end
