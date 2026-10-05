module Providers
  # A database receipt is the entire transport. This adapter never opens a network connection.
  class FakeEmail
    def deliver(operation)
      operation.fake_delivery || operation.create_fake_delivery!(
        provider_message_id: "fake-email-#{operation.id}", payload: operation.payload)
    end
  end
end
