# Ox_fuel Beta Agent Guide

## Scope

These instructions apply to the entire `Ox_fuel beta` resource. This version expands ox_fuel with server-authoritative volume pricing, vehicle tank and EV battery profiles, fuel grades, charging modes, cash/bank selection, pump and charger occupancy, physical nozzle/connector cables, positional San Andreas Sound audio, and a custom NUI meter.

## Project Map

- `config.lua`: Fuel grades, charging modes, payment methods, validation limits, pump leases, custom pump/charger locations, meter profiles, nozzle/connector settings, and vehicle capacities.
- `nozzle_offsets.lua`: Spawn-name/hash keyed vehicle nozzle profiles adapted from LC Fuel.
- `electric_profiles.lua`: Configured EV detection, battery capacity, and EV consumption profiles shared by client and server.
- `fuel_grades.lua`: Grade resolution, premium blending, and consumption multipliers.
- `vehicle_profiles.lua`: Vehicle class/model tank capacities and consumption rates.
- `client/fuel.lua`: Timed vehicle and fuel-can sessions, animations, cancellation controls, and live meter payloads.
- `client/meter.lua`: NUI transport, display units, pump presentation profiles, and result lifetime.
- `client/checkout.lua`: Grade and payment selection.
- `client/custom_pumps.lua`: Local static pump spawning, existing-prop reuse, per-pump hose reach, and resource-stop cleanup.
- `client/ron_pumps.lua`: Reversible map RON replacement, inherited base/heading, own-prop damage, occupied-source streaming retention, and map-hide restoration.
- `client/station_display.lua`: Shared independent world-screen surfaces for Sentinel and RON, including rear-facing register winding and keyboard checkout.
- `client/chargers.lua`: Local static charger spawning, existing-prop reuse, cable reach, synchronized electrical failure effects, and resource-stop cleanup.
- `client/charger_hardware.lua`: Visible docked connectors/cables, same-entity handoff to charging, portable observer state, streaming cleanup, and restrained night lighting.
- `client/prop_impacts.lua`: Shared crosshair-ray and predicted vehicle-impact detection for resource-spawned pumps and chargers.
- `client/charging.lua`: Connector, cable, occupancy lease, charging session, positional sound, live meter, and cleanup behavior.
- `client/nozzle.lua`: Nozzle, rope, synchronized pump lease, positional sound, and cleanup behavior.
- `client/nozzle_mounts.lua`: Cached model overrides, automatic safe-bone detection, body fallback, and offset debugging.
- `client/target.lua`: Pump, nozzle, vehicle, can, and options targets.
- `pump_slots.lua` / `pump_flow.lua`: Shared dual-slot identity and server-authoritative variable-flow accounting.
- `server.lua`: Authoritative sessions, pricing, payments, inventory metadata, dual pump leases, and vehicle state updates.
- `web/`: Compact pump register, logos, theme variants, state styling, and numeric tank/can level.
- `README.md`: Full behavior, configuration, framework integration, and changes from upstream.
- `THIRD_PARTY_NOTICES.md`: CDN-Fuel GPL asset inventory and LC Fuel coordinate, EV-list, and nozzle-profile attribution.
- Sibling `ox_fuel_assets`: Persistent original DRS Sentinel model/YTYP companion that must remain running during live `ox_fuel` restarts.
- `ox_fuel/development/sentinel_ev_station`: Original Sentinel Blender builders, native exports, geometry contracts, previews, and hardware lifecycle tests.

## Compatibility Boundaries

- Keep the existing `ox_fuel` events and exports for compatibility. Do not bulk-rename them to a beta namespace.
- Preserve `LICENSE` and `THIRD_PARTY_NOTICES.md`. Retained CDN-Fuel gas sounds require attribution; DRS EV geometry/audio are original GPL-3.0 contributions. Do not restore the removed legacy electric models or charging sounds.
- Keep electric YDR/YTYP files in the sibling `ox_fuel_assets` resource and retain the manifest dependency. Do not move them back into `ox_fuel`; live archetype unmounting crashes connected clients.
- Keep RON YDR/YTYP assets in that persistent companion too. Replacement code must never delete borrowed map/MLO/script-owned pumps, must restore every model hide on stop, and must not stream out a source with a held/attached hose.
- Preserve the beta resource and sound identifiers unless the user explicitly requests a namespace migration.
- The `fuel` vehicle state remains a `0` to `100` percentage for compatibility, even though transfer and pricing calculations use gallons internally.
- Preserve `fuelPremiumRatio` as a proportional `0.0` to `1.0` blend. A premium top-up must not convert the entire tank to premium.
- Configured EVs use the same `fuel` percentage as battery state, must not accept gas or jerry-can fuel, and must ignore Premium consumption multipliers.
- Configured EVs use explicit RPM/speed battery drain. Keep native consumption disabled for EVs so models with a petrol tank do not drain twice.
- Preserve automatic Qbox, QBCore, and ESX bank support and the custom payment-provider export.
- Cash remains the ox_inventory `money` item unless configuration or an integration explicitly changes it.

## Server Authority

- The server owns prices, flow rates, tank capacity, payment validation, transferred volume, fuel-can durability, and premium blending.
- The server also owns charging mode, kWh flow, battery capacity, payment validation, delivered energy, and final battery percentage.
- Never accept a client-supplied final price, volume, balance, capacity, or fuel result as authoritative.
- Keep fueling and fuel-can actions tied to short-lived server sessions.
- Validate player, pump, and vehicle proximity before starting and finishing sessions.
- Release pump leases on success, cancellation, timeout, disconnect, resource stop, and every abort path.
- Revalidate balances immediately before charging and apply payment and fuel changes no more than once.
- Keep session timing tolerant enough for latency but resistant to instant-completion requests.
- Charger dock state is cosmetic but still requires the matching owner's valid, unexpired charger lease/token. Keep the first occupancy snapshot return value compatible; the second value contains taken connector slots.

## Nozzle, Hose, And Sound

- Preserve model-specific pump heights and offsets in `config.lua`; users tune these values in game.
- Preserve the nozzle mount resolution order: explicit model profile, safe fuel bones, then configurable body fallback. Unsafe wheel, engine, and chassis bones require an explicit model profile.
- Do not undo custom pump offsets, spawned pump locations, rope overrides, or station data while changing unrelated behavior.
- Keep custom static pumps non-networked. Their model-and-coordinate occupancy key provides multiplayer synchronization without duplicating props through OneSync.
- Keep resource-created custom pumps and chargers natively invincible. Use the shared scripted impact detector, delete a gas pump before creating its explosion, synchronize destroyed locations through the server, and never delete a reused map or MLO prop.
- Keep charger failures electrical rather than explosive. Synchronize the destroyed station, release its lease, disable its target, abort active charging, and clean up every particle effect on resource stop.
- On resource stop or pump destruction, remove active hoses/cables and held props before deleting their source pump or charger entity.
- Delete only pump props created by this resource. A nearby map/MLO prop reused by the loader is not resource-owned.
- Hose failure must degrade to a usable nozzle instead of blocking fueling.
- Every abort path must stop managed refueling audio and clean up nozzle objects, ropes, textures, animations, leases, and meter state.
- Apply the same rule to charging connectors, cables, managed charging audio, charging sessions, and charger leases.
- Docked hardware must hand off the actual visible connector and stop owning that entity. Charging cleans up the held entity; hardware cleans up only its remaining parked props. Never unload the persistent model resource during a live fuel-resource restart.
- Attached nozzle and connector sessions must not disable movement, firing, aiming, weapon selection, or X. The vehicle target removal action is their normal player-controlled cancellation path; hand-held and fuel-can flows retain X cancellation and control restrictions.
- Managed San Andreas Sound loops must have stable IDs and explicit stop calls.
- Fueling completion and nozzle return must not leave the refueling loop playing.

## Meter And UI

- Sentinel defaults to cabinet-only UI, including checkout. Never restore its HUD merely because a screen is loading, small, off-camera, or distant. Keep keyboard cancellation available and reject a checkout if its DUI cannot load. Gas and portable HUD/focus behavior must remain unchanged.
- The RON replacement also defaults to model-only registers; ordinary gas HUDs remain unchanged. Route the leased nozzle/can slot to the corresponding front/rear screen, and preserve existing station/portable presentation when editing shared rendering or dock code.
- EV audio is served from this resource through San Andreas Sound. Station and portable loops use distinct logical IDs; stop both on every abort, return, completion, and restart.

- Keep the meter compact at approximately 320 px and retain the logo/register two-column layout.
- Keep pump logos unframed and selected by pump model through `fuelMeter.pumpDisplays`. Preserve original artwork in `web/logos/`; runtime mappings use the optimized 256 px copies in `web/logos/ui/`.
- Preserve modern seven-segment and vintage mechanical-flip register treatments.
- Use explicit meter states: `ready`, `fueling`, `complete`, and `stopped`.
- The register has a recessed dark lower details section instead of a separate footer. It contains status and unit price on the first row, then numeric tank/can percentage and grade/payment on the second row.
- The details section has no status dot. State is communicated through restrained text color and a subtle fueling-only pulse.
- Do not restore an ox_lib progress bar while the custom meter is handling fuel-can purchase or refill. Preserve animation, movement/combat restrictions, server timing, and X-to-cancel behavior through the custom control loop.
- Pump-nozzle final values remain displayed until the nozzle is returned or another meter state replaces them.
- Keep brand accents restrained. Structural surfaces should remain neutral, while state, one trim edge, digits, or the numeric level may carry brand color.
- Keep `Sale`, volume, unit price, grade, and payment labels readable at game scale without widening the meter.
- Update both runtime payloads and local preview profiles when changing meter fields.
- Avoid whole-panel movement. Brief digit settling and the fueling status pulse are the intended animations.

## Coding Conventions

- Follow the existing Lua module pattern and keep helpers local unless another module genuinely needs them.
- Use state flags and run/session IDs to prevent stale threads from controlling a newer fueling operation.
- Check entity existence before native calls and network IDs before server requests.
- Add localized strings for new player-facing labels and notifications.
- Keep configuration values editable rather than embedding pump models, prices, offsets, or capacities in runtime code.
- Add dependencies and NUI files to `fxmanifest.lua` when required.
- Update `README.md` whenever behavior, configuration, framework support, or UI semantics change.

## Validation

Run syntax checks that support the files being changed:

```powershell
node --check web\app.js
luac -p client\custom_pumps.lua
luac -p client\fuel.lua
luac -p client\meter.lua
luac -p client\nozzle.lua
```

Use the built-in local previews for visual checks:

```text
web/index.html?preview=vintage
web/index.html?preview=xero-modern
web/index.html?preview=can-refill
web/index.html?preview=charging
```

Check that the UI has no horizontal or vertical overflow, labels fit, logos load, and the browser console has no errors. Then verify in FiveM:

- Every configured pump model can be targeted and receives the correct logo/theme.
- Custom pump props spawn once at the configured position and heading, remain usable, and disappear on resource stop without deleting reused map props.
- A custom pump's configured hose reaches its override distance while ordinary map pumps retain the global nozzle range.
- Ordinary gas pumps and EV chargers support two simultaneous leases; `prop_vintage_pump` remains single-slot.
- Starting a second transfer slows both sessions, and ending either restores the remaining session without retroactive volume changes.
- Cash and bank payments work on the active framework.
- Regular and Premium pricing, blending, and mileage multipliers are correct.
- Different vehicle classes use their configured capacity and transfer duration.
- The numeric tank/can percentage starts at the current target level and updates correctly.
- Can purchase/refill uses only the custom meter and still cancels with X.
- Nozzle and can final values settle on the server-confirmed result.
- Fueling sounds stop at full tank, cancel, lease loss, nozzle return, and resource stop.
- Charging props spawn at all configured LC Fuel coordinates, configured EVs cannot use gas, non-EVs cannot charge, and Standard/Rapid kWh pricing matches the server result.
- Damaging a resource-owned charger synchronizes its flash, sparks, smoke, disabled target, and released lease; restarting the resource removes effects and restores the station.
- Charging sounds stop at full battery, cancel, cable range failure, lease loss, connector return, disconnect, and resource stop.
- Repeated use and resource restart leave no objects, ropes, sounds, leases, prompts, or stale UI behind.
