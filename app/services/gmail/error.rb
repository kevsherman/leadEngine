module Gmail
  class Error < StandardError
    attr_reader :code
    def initialize(code = "gmail_unavailable")
      @code = code
      super(code) # Never propagate Google response bodies, tokens, or customer data.
    end
  end
end
