# ox_fuel Expanded

An independent community expansion of [CommunityOx ox_fuel v1.5.2](https://github.com/CommunityOx/ox_fuel/tree/v1.5.2). It combines physical fuel nozzles, EV charging, portable power, synchronized pumps, vehicle tank profiles, fuel grades, payment choices, positional audio, and branded pump displays in one resource.

This is not an official CommunityOx release. Keep the installed resource folder named `ox_fuel` for compatibility with existing exports and integrations.

Maintained source and downloads: [DrSnyder86/ox_fuel-Expanded](https://github.com/DrSnyder86/ox_fuel-Expanded)

## Highlights

- Physical fuel nozzles and EV connectors with hoses, cables, sounds, animations, and vehicle attachment.
- Automatic fuel-cap detection plus 669 adapted vehicle mount profiles and live offset editors.
- Regular and Premium grades, realistic class-based tank sizes, and configurable consumption rates.
- Cash and bank payment support for Qbox, QBCore, ESX, and custom providers.
- Modern and vintage pump interfaces with RON, LTD, XERO, and Globe Oil branding.
- Dedicated EV charging interface with Standard and Rapid charging.
- Purchasable, deployable, damageable, and rechargeable portable EV power unit.
- Synchronized pump occupancy, spawned custom pumps, scripted pump explosions, and electrical charger faults.
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
3. [Download and install San Andreas Sound Suite](https://drsnyder-fivem-site.pages.dev/scripts/san-andreas-sound-suite), then copy the seven `.ogg` files from `ox_fuel/assets/sounds` to `san_andreas_sound/web/sounds`.
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

## Configuration

The main settings are grouped in `config.lua`:

| Section | Purpose |
| --- | --- |
| `versionCheck` | GitHub manifest URL, download URL, startup delay, and console notices |
| `fueling` | Grades, prices, flow speed, and price precision |
| `payments` | Cash/bank options and defaults |
| `pumpOccupancy` | Pump leases and heartbeat timing |
| `fuelMeter` | Units, checkout method, logos, themes, and UI behavior |
| `nozzle` | Fuel nozzle, hose, sounds, attachment, anchors, and debug tools |
| `electric` | EV models, stations, charging modes, connector, cable, and blips |
| `electric.portable` | Portable pack item, capacity, prop, cable, purchase, and warnings |
| `customGasPumpLocations` | Spawned aircraft, marine, and remote pumps |
| `vehicleProfiles` | Tank capacities and consumption multipliers |
| `chaosMode` | Optional running-engine, drive-off, old-pump, and charging faults |

Fuel remains stored as a `0` to `100` vehicle state value for ox_fuel compatibility. Gallons, kWh, price, premium blend, and portable pack charge are calculated and validated by the server.

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

Compared with CommunityOx ox_fuel v1.5.2, this build adds:

- Physical nozzle, hose, connector, and cable systems.
- Positional fuel and charging sounds through `san_andreas_sound`.
- Live branded gas and EV interfaces with in-UI product and payment selection.
- Synchronized pump/charger occupancy and server-authoritative transactions.
- Vehicle tank capacities, EV batteries, fuel grades, premium blending, and payment adapters.
- Automatic and profile-based vehicle attachment with live offset editors.
- Spawned custom pumps and EV stations with synchronized damage behavior.
- Portable EV power, item metadata, purchase, deployment, charging, damage, and recharge flows.
- Persistent electric assets through the `ox_fuel_assets` companion.
- Optional, disabled-by-default Chaos Mode.
- Maintained-repository startup version checking.

## Testing Notes

Before using the resource on a live server, test representative gas vehicles, EVs, addon vehicles, framework payment accounts, custom pumps, resource restart, portable item metadata, and every enabled Chaos Mode outcome.

## Licensing and Credits

This project is distributed under GPL-3.0. See `LICENSE` and `THIRD_PARTY_NOTICES.md` before redistribution.

- Base resource: [CommunityOx ox_fuel](https://github.com/CommunityOx/ox_fuel)
- Electric models and selected sounds: [CDN-Fuel](https://github.com/CodineDev/cdn-fuel)
- Adapted vehicle offsets and station data: [LC Fuel](https://github.com/LeonardoSoares98/lc_fuel)

Free and source-available does not mean public domain. Keep the license, notices, and attribution with modified or redistributed copies.
