class DataSource < ApplicationRecord
  serialize :config, coder: JSON

  enum :status, { inactive: "inactive", active: "active", error: "error" }, default: "inactive"

  has_many :contracts

  validates :country_code,  presence: true
  validates :name,          presence: true
  validates :adapter_class, presence: true
  validates :source_type,   presence: true,
                            inclusion: { in: %w[api scraper csv] }

  def config_hash
    case config
    when Hash   then config
    when String then JSON.parse(config) rescue {}
    else {}
    end
  end

  def adapter
    adapter_class.constantize.new(config_hash)
  end
end
