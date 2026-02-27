# Actions Roadmap

## Rule-Based Scoring Actions (Track A)

- [x] A2/A3: Date-sequence anomaly (`celebration_date < publication_date`)
  - Implemented in `Flags::Actions::DateSequenceAnomalyAction`
  - Persists `Flag` records (`A2_PUBLICATION_AFTER_CELEBRATION`)
  - Includes stale-flag cleanup and idempotent upsert behavior
- [ ] A9: Price-to-estimate anomaly (`total_effective_price` vs `base_price`)
- [ ] A5: Threshold-splitting near legal cutoffs
- [ ] A1: Repeat direct awards (36-month window)
- [ ] A4: Amendment inflation
- [ ] A7: Abnormal direct-award rate vs peers
- [ ] A6: Single-bidder/low-competition
- [ ] A8: Long execution duration
