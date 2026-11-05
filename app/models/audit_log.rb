# Who changed what. Entries are written by the controllers as admins make changes.
class AuditLog < ApplicationRecord
  # Columns we never write to the log.
  SENSITIVE = %w[password_digest updated_at created_at].freeze

  belongs_to :user

  validates :action, presence: true

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :for_organization, ->(org) { joins(:user).where(users: { organization_id: org.id }) }

  # target is any record; its display name is kept in the log so it still reads
  # correctly after the record is renamed or deleted.
  def self.record!(actor, action, target, details = {})
    create!(user: actor, action: action, target_type: target&.class&.name, target_id: target&.id,
            details: { "target" => label_for(target) }.merge(details.deep_stringify_keys))
  end

  # { "name" => ["old", "new"] } for the last save of a record, minus anything sensitive.
  def self.diff(record) = record.saved_changes.except(*SENSITIVE)

  def self.label_for(target)
    return nil unless target
    target.try(:full_name) || target.try(:name) || "#{target.class.name} ##{target.id}"
  end

  def target_label = details["target"]
  def changes_hash = details.except("target")
end
