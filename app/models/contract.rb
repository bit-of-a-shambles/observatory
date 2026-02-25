class Contract < ApplicationRecord
  belongs_to :contracting_entity, class_name: "Entity"
  belongs_to :data_source, optional: true
  has_many :contract_winners, dependent: :destroy
  has_many :winners, through: :contract_winners, source: :entity

  validates :external_id, presence: true, uniqueness: true
  validates :object,       presence: true
end
