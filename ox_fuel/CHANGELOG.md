# Changelog

## 1.5.2-expanded.3 - Original hardware and shared stations

- Added the original DRS Sentinel EV station, connector, portable hardware, parked cables, cabinet-only checkout, synchronized pickup, and restrained night lighting.
- Added the original illuminated RON style-A replacement pump with dual docked handles, front/rear live registers, native night lighting, collision, damage synchronization, and reversible map-prop replacement.
- Added the original universal `drs_fuel_nozzle` model across every gas-pump brand while preserving existing hand, vehicle, holder, and hose transforms. The matching `ox_fuel_assets` companion is version `1.2.6`.
- Added two synchronized hose/connector slots to every configured gas pump and EV charger except `prop_vintage_pump`, with side-aware anchors and independently leased handles.
- Added configurable shared-use flow reduction that updates both active sessions and restores full speed when either side stops.
- Extended slot leasing to fuel-can and portable-power station transactions without treating idle handles as active flow.
- Replaced legacy interaction sweeps with a compact resource-local 13-file audio bank and stable, independently managed gas, station-EV, and portable sound IDs.
- Refined RON cabinet controls, physical checkout layout, docks, LOD distances, and Sentinel hardware presentation while retaining server-authoritative pricing and settlement.
- Removed the invalid entity-only physics activation from rope handles, preserving hose/cable creation and cleanup without the native crash path.

## 1.5.2-expanded.2 - Portable power and optional Chaos Mode

- Added the purchasable, deployable, damageable, rechargeable 12 kWh portable EV power unit with unique inventory metadata, physical connector/cable, positional audio, placement animations, and a compact interface.
- Enabled model-cached gas-nozzle and EV-connector attachment by default, added target-based removal, and kept players free to move and use weapons during attached transfers.
- Moved streamed EV archetypes into the persistent `ox_fuel_assets` companion so the main resource can restart without live-unloading those assets.
- Added transient charging faults and the experimental `chaosMode` configuration. The master switch defaults to off; server-side rolls, major-event cooldowns, one-event session guards, and delivered-only settlement protect normal gameplay and economies.
- Added running-engine consequences, hose drive-off outcomes, vintage pump flow/click-off quirks, Rapid charging protection faults, and portable-pack thermal shutdowns.
- Expanded the gas and EV interfaces, portable purchase/recharge workflow, destruction cleanup, offset tools, later-build EV list, documentation, item images, and release-post material.
- Replaced the large offset input dialog with a compact side-scroll editor that updates the attached preview prop immediately.
- Standardized the portable inventory item on `portable_ev_charger_compact.png` and condensed the README into an installation-focused guide.

## 1.5.2-expanded.1 - Community preview

- Added physical pump nozzles, configurable hoses, positional sounds, and synchronized pump occupancy.
- Added 669 attributed LC Fuel vehicle nozzle profiles, automatic safe fuel-bone detection, model caching, side-aware orientation, configurable fallback mounting, and an opt-in offset generator.
- Added custom aircraft, marine, and remote pump spawning with per-location hose reach.
- Added electric vehicle charging with streamed charger assets, station blips, occupancy, Standard/Rapid modes, and kWh pricing.
- Added configurable vehicle tank and EV battery capacities with class/model consumption tuning.
- Added Regular/Premium grades, Cash/Bank selection, premium blending, and framework payment adapters.
- Added a branded modern/vintage pump register with live sale, volume, tank level, fuel grade, payment, and charging information.
- Added server-authoritative fueling, charging, and fuel-can sessions with cleanup and validation.
- Kept vehicle nozzle/connector attachment as experimental toggles disabled by default.
