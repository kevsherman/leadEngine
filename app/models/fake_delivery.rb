class FakeDelivery < ApplicationRecord
  belongs_to :send_operation
  validates :send_operation_id, uniqueness: true
end
