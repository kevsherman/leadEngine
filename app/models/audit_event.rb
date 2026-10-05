class AuditEvent < ApplicationRecord
  belongs_to :conversation
  belongs_to :operator, optional: true
end
