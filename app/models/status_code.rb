class StatusCode < ApplicationRecord
  belongs_to :status

  validates :phone_code, presence: true, uniqueness: { scope: :status_id, case_sensitive: false }
end
