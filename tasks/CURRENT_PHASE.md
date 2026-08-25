# Current Phase

**Phase 7 — Passenger Demand and Pricing: COMPLETE** (2026-08-25)

Delivered: DemandSystem (gravity x seasonality x weekday x economy pools;
exponential price-utility share allocation with outside option; schedule/
comfort/operations quality factors; conserved allocation onto routes);
booking at boarding, revenue at departure, load-factor stats; economic
calibration anchored to GAME_BALANCE and enforced by automated economy
tests (interior revenue optimum, undercutting, market splitting,
seasonality, economy index). Save v5.

**Build:** clean. **Tests:** 130/130. Design note: power-law elasticities
were rejected during this phase (unbounded monopoly revenue); exponential
utilities give a finite optimum — see docs/ECONOMY.md.

**Next phase: Phase 8 — Finance and Airline Economics** (task AE-009).
