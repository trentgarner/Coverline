class Organization < ApplicationRecord
  has_many :teams, dependent: :destroy
  has_many :users, dependent: :destroy

  has_many :statuses, dependent: :destroy
  has_many :unmatched_events, dependent: :destroy

  UNMAPPED_NAME = "Unmapped".freeze

  validates :name, presence: true
  validates :timezone, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name } }, message: "isn't a known time zone" }

  # --- Phone-system API key (section 5): only a digest is kept, so a key can't be read back. ---

  # Creates a new key, replacing any old one, and returns it. This is the only time it is available.
  def generate_api_key!
    key = "cvl_#{SecureRandom.urlsafe_base64(32)}"
    update!(settings: settings.merge("api_key_digest" => self.class.digest_key(key), "api_key_prefix" => key.first(8),
                                     "api_key_created_at" => Time.current.iso8601))
    key
  end

  def api_key? = settings["api_key_digest"].present?
  def api_key_prefix = settings["api_key_prefix"]
  def api_key_created_at = settings["api_key_created_at"]&.then { |t| Time.zone.parse(t) }

  def self.digest_key(key) = Digest::SHA256.hexdigest(key.to_s)

  def self.find_by_api_key(key)
    return nil if key.blank?
    where("settings ->> 'api_key_digest' = ?", digest_key(key)).first
  end

  # The catch-all status for phone codes nobody has mapped yet. Created the first time it is needed.
  def unmapped_status
    existing = statuses.find_by(id: settings["unmapped_status_id"])
    return existing if existing
    status = statuses.find_or_create_by!(name: UNMAPPED_NAME) do |s|
      s.category = "other"
      s.color = "#ffc107"
      s.sort_order = (statuses.maximum(:sort_order) || 0) + 1
    end
    update!(settings: settings.merge("unmapped_status_id" => status.id))
    status
  end

  def unmapped_status?(status) = status.id == settings["unmapped_status_id"]
end
