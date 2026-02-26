# frozen_string_literal: true

# Seeds register the known data sources. Status starts as inactive;
# run ImportService manually or via a scheduled job to activate them.

sources = [
  {
    country_code:  "PT",
    name:          "Portal da Transparência SNS",
    source_type:   "api",
    adapter_class: "PublicContracts::PT::SnsClient",
    config:        nil
  },
  {
    country_code:  "PT",
    name:          "Portal BASE",
    source_type:   "api",
    adapter_class: "PublicContracts::PT::PortalBaseClient",
    config:        nil
  },
  {
    country_code:  "PT",
    name:          "TED — PT",
    source_type:   "api",
    adapter_class: "PublicContracts::EU::TedClient",
    config:        { "country_code" => "PRT" }.to_json
  }
]

sources.each do |attrs|
  ds = DataSource.find_or_initialize_by(name: attrs[:name], country_code: attrs[:country_code])
  ds.assign_attributes(
    source_type:   attrs[:source_type],
    adapter_class: attrs[:adapter_class],
    config:        attrs[:config],
    status:        ds.new_record? ? "inactive" : ds.status
  )
  ds.save!
  puts "#{ds.persisted? && !ds.previously_new_record? ? 'Updated' : 'Created'}: #{ds.name} (#{ds.country_code})"
end

puts "\nSeeded #{sources.size} data sources."
