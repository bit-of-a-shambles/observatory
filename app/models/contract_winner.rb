class ContractWinner < ApplicationRecord
  belongs_to :contract
  belongs_to :entity
end
