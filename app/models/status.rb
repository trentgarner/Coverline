class Status < ApplicationRecord
  CATEGORIES = %w[ready on_call wrap_up break lunch meeting offline other].freeze
  # Plan section 3/6: Available/Idle and On Call count toward CFT; Ready, On Call and Wrap Up are "productive".
  CFT_CATEGORIES = %w[ready on_call].freeze
  PRODUCTIVE_CATEGORIES = %w[ready on_call wrap_up].freeze

  belongs_to :organization
  has_many :status_codes, dependent: :destroy
  has_many :status_events, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: false }
  validates :color, format: { with: /\A#\h{6}\z/, message: "must be a hex color like #2f9e6f" }
  validates :category, inclusion: { in: CATEGORIES }
  validates :time_limit_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :phone_codes_are_unique_in_organization

  # What the two checkboxes start as for a category (the admin can change them).
  def self.flag_defaults_for(category)
    { productive: PRODUCTIVE_CATEGORIES.include?(category.to_s), counts_toward_cft: CFT_CATEGORIES.include?(category.to_s) }
  end

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :name) }

  # Phone codes as one editable text block (one per line). Saved together with the status.
  attr_writer :phone_codes_text

  def phone_codes_text
    @phone_codes_text || status_codes.map(&:phone_code).join("\n")
  end

  def phone_code_list
    (@phone_codes_text || phone_codes_text).split(/[\n,;]+/).map(&:strip).reject(&:blank?).uniq { |c| c.downcase }
  end

  # Saves the status and replaces its phone codes in one transaction.
  def save_with_codes
    return false unless valid?
    transaction do
      save!
      if @phone_codes_text
        wanted = phone_code_list
        status_codes.where.not(phone_code: wanted).destroy_all
        (wanted - status_codes.reload.map(&:phone_code)).each { |c| status_codes.create!(phone_code: c) }
      end
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  private

  def phone_codes_are_unique_in_organization
    return unless organization_id && @phone_codes_text
    taken = StatusCode.joins(:status).where(statuses: { organization_id: organization_id })
    taken = taken.where.not(status_id: id) if persisted?
    clashes = phone_code_list.select { |c| taken.exists?([ "lower(status_codes.phone_code) = ?", c.downcase ]) }
    errors.add(:phone_codes_text, "already used by another status: #{clashes.join(', ')}") if clashes.any?
  end
end
