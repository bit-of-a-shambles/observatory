class DataSource < ApplicationRecord
  serialize :config, coder: JSON

  enum :status, { inactive: "inactive", active: "active", error: "error" }, default: "inactive"

  scope :active_sources, -> { where(status: :active) }
  scope :portal_base, -> { where(adapter_class: "PublicContracts::PT::PortalBaseClient") }

  has_many :contracts

  validates :country_code,  presence: true
  validates :country_code,  format: { with: /\A[A-Z]{2}\z/, message: "must be a 2-letter ISO 3166-1 alpha-2 code (e.g. PT, ES)" }
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

  ADAPTER_NAMESPACE = "PublicContracts::"

  def adapter
    unless adapter_class.start_with?(ADAPTER_NAMESPACE)
      raise ArgumentError, "adapter_class must be within the PublicContracts namespace"
    end
    klass = adapter_class.constantize
    unless klass.method_defined?(:fetch_contracts)
      raise ArgumentError, "#{adapter_class} does not implement #fetch_contracts"
    end
    klass.new(config_hash)
  end
end
