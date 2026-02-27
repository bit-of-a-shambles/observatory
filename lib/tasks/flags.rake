# frozen_string_literal: true

namespace :flags do
  desc "Run the first scoring action (A2/A3 date-sequence anomaly)"
  task run_first_action: :environment do
    flagged = Flags::Actions::DateSequenceAnomalyAction.new.call
    puts "A2/A3 date-sequence anomalies flagged: #{flagged}"
  end
end
