# ox_fuel Expanded

An independent community expansion of [CommunityOx ox_fuel v1.5.2](https://github.com/CommunityOx/ox_fuel/tree/v1.5.2). It combines physical fuel nozzles, EV charging, portable power, synchronized pumps, vehicle tank profiles, fuel grades, payment choices, positional audio, and branded pump displays in one resource.

This is not an official CommunityOx release. Keep the installed resource folder named `ox_fuel` for compatibility with existing exports and integrations.

Maintained source and downloads: [DrSnyder86/ox_fuel-Expanded](https://github.com/DrSnyder86/ox_fuel-Expanded)

## Highlights

- Original DRS Sentinel hardware: dual-screen cabinet, matching connector, portable pack, and visible docked cables.
- Beta RON style-A pump: off-white cabinet, illuminated branding/amber trim, two real docked fuel nozzles, and front/rear live registers.
- Physical fuel nozzles and EV connectors with hoses, cables, sounds, animations, and vehicle attachment.
- Original universal DRS fuel nozzle: graphite rubber body, metal trigger/spout, and reinforced hose union across all gas pumps.
- Automatic fuel-cap detection plus 669 adapted vehicle mount profiles and live offset editors.
- Regular and Premium grades, realistic class-based tank sizes, and configurable consumption rates.
- Cash and bank payment support for Qbox, QBCore, ESX, and custom providers.
- Modern and vintage pump interfaces with RON, LTD, XERO, and Globe Oil branding.
- Dedicated EV charging interface with Standard and Rapid charging.
- Purchasable, deployable, damageable, and rechargeable portable EV power unit.
- Two synchronized nozzle slots on every gas pump and EV charger except the single-handle vintage pump.
- Shared-pump flow slowdown, spawned custom pumps, scripted pump explosions, and electrical charger faults.
- Optional Chaos Mode with server-side chance rolls and economy-safe interrupted settlement.
- Configurable startup version check against the maintained GitHub package.

## Requirements

- `ox_lib`
- `ox_inventory`
- `ox_target`
- [`san_andreas_sound` - San Andreas Sound Suite](https://drsnyder-fivem-site.pages.dev/scripts/san-andreas-sound-suite)
- Included `ox_fuel_assets` companion resource

## Installation

1. Install the included `ox_fuel` and `ox_fuel_assets` folders.
2. Disable any other fuel resource.
3. [Download and install San Andreas Sound Suite](https://drsnyder-fivem-site.pages.dev/scripts/san-andreas-sound-suite). The included `drs_*.ogg` sounds are served directly from ox_fuel and need no extra copying. Alternate sound providers may require installing the clips into their own sound folder. Sound sources and licenses are listed in `THIRD_PARTY_NOTICES.md`.
4. Review prices, pump locations, EV models, vehicle profiles, and payment settings in `config.lua`.
5. Add the portable charger item from `install/ox_inventory_items.lua` to `ox_inventory/data/items.lua`.
6. Copy `install/images/portable_ev_charger_compact.png` to `ox_inventory/web/images`.
7. Start the resources in this order:

```cfg
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure san_andreas_sound
ensure ox_fuel_assets
ensure ox_fuel
```

The first move from an older build that streamed the electric assets inside `ox_fuel` requires a full server restart. After that, `ox_fuel` can be restarted while `ox_fuel_assets` stays mounted. Stop or update the companion resource only during a full server restart.

The DRS model-name migration also requires a full server/client restart. Do not hot-restart the companion. Legacy CDN charging models and charging-only sounds are no longer included; gas sounds and their attribution remain.

## Configuration

The main settings are grouped in `config.lua`:

| Section | Purpose |
| --- | --- |
| `versionCheck` | GitHub manifest URL, download URL, startup delay, and console notices |
| `fueling` | Grades, prices, flow speed, and price precision |
| `payments` | Cash/bank options and defaults |
| `pumpOccupancy` | Dual-nozzle slots, single-model exclusions, shared flow speed, leases, and heartbeat timing |
| `fuelMeter` | Units, checkout method, logos, themes, and UI behavior |
| `nozzle` | Fuel nozzle, hose, sounds, attachment, anchors, and debug tools |
| `ronPump` | Style-A RON replacement, physical registers, docks, illumination, and damage locations |
| `electric` | EV models, stations, charging modes, connector, cable, and blips |
| `electric.portable` | Portable pack item, capacity, prop, cable, purchase, and warnings |
| `customGasPumpLocations` | Spawned aircraft, marine, and remote pumps |
| `vehicleProfiles` | Tank capacities and consumption multipliers |
| `chaosMode` | Optional running-engine, drive-off, old-pump, and charging faults |

Fuel remains stored as a `0` to `100` vehicle state value for ox_fuel compatibility. Gallons, kWh, price, premium blend, and portable pack charge are calculated and validated by the server.

Sentinel sessions use the physical cabinet screen only. Choose options with the arrow keys, confirm with Enter, or cancel with Backspace. Ordinary gas pumps and portable power keep their screen HUDs. `electric.stationDisplay.hudFallback = true` optionally restores the distance/readability fallback. EV clips and volumes are configurable in `electric.sounds`.

`ronPump.enabled = true` replaces nearby map RON `prop_gas_pump_1a` props with the original `drs_gas_pump_ron`, inheriting their base position and heading. It hides/restores map props rather than deleting them; script-owned custom pumps and other brands are untouched. Set it to `false` and restart only ox_fuel to restore the stock pumps while the asset companion stays mounted. RON checkout/live totals use its physical register by default, with the same arrow/Enter/Backspace controls as Sentinel. Docks, lights, display, and placement corrections are grouped under `ronPump`. Damage synchronization validates listed station/custom-pump coordinates; add unlisted MLO pump coordinates to `ronPump.damageLocations` for synchronized destruction.

Each pump normally exposes two independently synchronized handles. `prop_vintage_pump` remains single-handle through `pumpOccupancy.singleNozzleModels`. When both slots are actively transferring fuel or energy, both sessions use `pumpOccupancy.sharedFlowMultiplier`; holding an unused nozzle does not reduce the other side's speed.

The replacement RON pump chooses its front/rear register from the player's approach side, regardless of the leased nozzle slot (`ronPump.stationDisplay.useApproachSide`).

The version checker runs once at server startup and prints only when a newer package is available unless `notifyCurrent` or `verboseErrors` is enabled. Set `versionCheck.enabled = false` to disable it. Each public update must also bump `version` in `ox_fuel/fxmanifest.lua` on GitHub.

### Payment Support

Cash uses the `money` item in ox_inventory. Bank support is detected through Qbox, QBCore, or ESX. Custom integrations can use the existing `setPaymentProvider`, `setPaymentMethod`, and `setMoneyCheck` exports.

### Custom Pumps

Entries in `customGasPumpLocations` accept a pump prop, `vector4` location, and optional `ropeLength`. The model must also be present in `pumpModels`. Resource-spawned pumps use synchronized occupancy and scripted impact destruction.

### Chaos Mode

`chaosMode.enabled` defaults to `false`. When enabled, it can add running-engine hazards, hose drive-off damage, vintage pump quirks, Rapid charger faults, and portable pack thermal shutdowns. Chance rolls are server-side, serious outcomes use cooldowns, and players are charged only for fuel or energy already delivered.

## Nozzle Offset Editor

Set `nozzle.offsetDebug.enabled = true`, aim at a vehicle, and use:

- `/ox_fuel_nozzleoffset` for the fuel nozzle.
- `/ox_fuel_chargeroffset` for the EV connector.
- `/ox_fuel_debugcaps` for nearby mount markers and missing-model reports.

Press G to open the compact editor. Use Up/Down to select Bone, Distance, position, or rotation, then Left/Right to adjust it. The real preview prop updates immediately. Backspace closes the adjustment menu so the result can be inspected. Press E to print and copy the ready-to-paste vehicle profile. Backspace again closes the editor and removes the preview.

Mount resolution uses this order:

1. Model-specific profile in `nozzle_offsets.lua`.
2. `petrolcap`.
3. `petroltank`, `petroltank_l`, or `petroltank_r`.
4. Configurable body fallback.

Automatic detection does not attach to wheel, engine, or chassis bones. Those bones are accepted only in explicit model profiles.

## Portable EV Charger

The portable unit uses a unique non-stackable inventory item with its remaining charge stored in metadata. Players can purchase it at an EV station, deploy it, connect it to an EV, pick it up, damage it, and recharge it at a normal charging station.

Use the supplied item definition and the single included image:

```text
install/ox_inventory_items.lua
install/images/portable_ev_charger_compact.png
```

Keep `stack = false` so each unit retains independent charge metadata.

## Local Changes From Original

- Universal `drs_fuel_nozzle` replaces the runtime stock fuel nozzle on all brands, vintage units, and custom pumps, including the visible RON docks. Its original geometry retains the existing hand/vehicle frame and hose exit; tuned offsets, sounds, and transfer behavior are unchanged. Install the matching `ox_fuel_assets` 1.2.6 companion during a full server/client restart, never a live companion restart. `nozzle.model` remains configurable.
- Compact 13-file audio bank: dry recorded handling cues and shared connector/relay sounds replace the synthesized sweeps. Gas, station EV, and portable loops are unchanged. Holder/vehicle/device emitters and short one-shot ranges follow the physical action; gas completion has no extra chime. Unused legacy sounds are removed, with historical credits retained. Install the matching config, client scripts, and complete sound folder together.
- RON cabinet/control refinement: near-flush fascia and aligned live screens, continuous rounded amber trim, outward-angled front/rear underside diffusers, no white header edge, softly backlit grade faces/keypad legends, and a cosmetic model-only Diesel button. Accepted dimensions, docks, collision, sound, checkout choices, and Sentinel assets are unchanged.
- Fuel hoses and EV cables use rope natives only; their handles are no longer passed to the entity-only `ActivatePhysics` native. Attachment, offsets, and cleanup behavior are unchanged.
- RON uses model-native night illumination; `ronPump.lighting.enabled` remains false so its former scripted hotspots do not render. Two short-range, non-shadowed underside lights replace the original central emitter; Sentinel lighting is unchanged.
- RON side badges are raised clear of the docked nozzles; gray lower-panel screw/lock details are removed. The physical register has slightly more depth clearance and larger transaction labels.
- Sentinel docked connectors are recessed 3 cm with matching parked cable ends. Emissive accents are stronger; nearby night spill uses distributed strip samples, limited to the two closest cabinets with a distance fade.
- Original-size RON polish: inward-facing docked nozzles, fitted holders, transparent side badges, and raised/recessed controls. Gas and EV keyboard selection includes a highlighted Confirm row.
- Resource-local gas/EV cues keep configurable volumes and stable managed-loop cleanup; shared filenames do not merge independent station/portable sound IDs.
- RON cabinet spawning extends to 140 m with 180 m exit hysteresis and the existing 12-pump cap. RON/Sentinel low-detail visibility extends to 180 m; near-detail LODs, docks, lighting, and live-screen ranges stay bounded. Tune `ronPump.spawnDistance`, `despawnDistance`, `modelLodDistance`, and `electric.modelLodDistance` for the server's hardware.
- On approach, map RON replacements still wait for GTA's original prop to stream in. The 140 m spawn range is a ceiling, not a forced map-streaming distance; already spawned replacements remain visible farther when departing.

- RON physical-screen checkout rows reserve space for grade, price, payment, and confirmation without overlap; the original-size replacement model and offsets are retained.

Compared with CommunityOx ox_fuel v1.5.2, this build adds:

- Physical nozzle, hose, connector, and cable systems.
- Positional fuel and charging sounds through `san_andreas_sound`.
- Bottom-right branded gas and EV interfaces with in-UI product and payment selection.
- Dual-slot pump/charger occupancy, shared-use flow reduction, and server-authoritative transactions.
- Vehicle tank capacities, EV batteries, fuel grades, premium blending, and payment adapters.
- Automatic and profile-based vehicle attachment with live offset editors.
- Spawned custom pumps and EV stations with synchronized damage behavior.
- Portable EV power with a compact vertical battery display, item metadata, purchase, deployment, charging, damage, and recharge flows.
- Persistent electric assets through the `ox_fuel_assets` companion.
- Original `drs_ev_*` Sentinel station/portable models, faceted open-grip connector, docked cables, synchronized pickup, softly illuminated trim/labels, and cabinet-only station UI (beta only).
- Sentinel station uses separate static type/include collision masks covering vehicle bodies, wheels, and pedestrians; scripted electrical damage remains independent of physical collision.
- Configurable, reversible RON map-pump replacement with original emissive logo/trim materials, dual docked universal nozzles, shaped idle hoses, independent front/rear registers, vehicle/wheel collision, and synchronized scripted damage at validated station locations.
- Shared dry EV interaction cues, separate station/portable managed loops, and resource-local playback through San Andreas Sound.
- Optional, disabled-by-default Chaos Mode.
- Maintained-repository startup version checking.

## Testing Notes

Before using the resource on a live server, test representative gas vehicles, EVs, addon vehicles, both sides of ordinary pumps and chargers, the single-slot vintage pump, shared flow transitions, framework payment accounts, custom pumps, resource restart, portable item metadata, and every enabled Chaos Mode outcome.

## Licensing and Credits

This project is distributed under GPL-3.0. See `LICENSE` and `THIRD_PARTY_NOTICES.md` before redistribution.

- Base resource: [CommunityOx ox_fuel](https://github.com/CommunityOx/ox_fuel)
- Selected gas sounds: [CDN-Fuel](https://github.com/CodineDev/cdn-fuel)
- Original DRS Sentinel models, preserved loops, and device tones: ox_fuel Expanded contributors. Recorded foley sources and their licenses are credited in `THIRD_PARTY_NOTICES.md`.
- Adapted vehicle offsets and station data: [LC Fuel](https://github.com/LeonardoSoares98/lc_fuel)

Free and source-available does not mean public domain. Keep the license, notices, and attribution with modified or redistributed copies.
