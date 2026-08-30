# ox_fuel Expanded 1.5.2-expanded.2

An expanded, drag-and-drop replacement for CommunityOx ox_fuel v1.5.2. This package adds physical nozzles and hoses, EV charging, portable EV power, synchronized pumps, fuel grades, payment choices, vehicle tank profiles, branded interfaces, positional audio, and optional Chaos Mode.

Keep the installed fuel resource folder named `ox_fuel` for compatibility.

## Package Contents

- `ox_fuel` - the main fuel and charging resource.
- `ox_fuel_assets` - persistent streamed props used by electric charging. Keep this resource mounted when restarting `ox_fuel`.

## Requirements

- `ox_lib`
- `ox_inventory`
- `ox_target`
- [`san_andreas_sound` - San Andreas Sound Suite](https://drsnyder-fivem-site.pages.dev/scripts/san-andreas-sound-suite)

## Quick Install

1. Copy both resource folders into your server resources directory.
2. Disable any other fuel resource.
3. Add the portable charger item from `ox_fuel/install/ox_inventory_items.lua` to `ox_inventory/data/items.lua`.
4. Copy `ox_fuel/install/images/portable_ev_charger_compact.png` to `ox_inventory/web/images`.
5. Copy the seven `.ogg` files from `ox_fuel/assets/sounds` to `san_andreas_sound/web/sounds`.
6. Review `ox_fuel/config.lua`, then start the resources in this order:

```cfg
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure san_andreas_sound
ensure ox_fuel_assets
ensure ox_fuel
```

Use a full server restart for the first installation or whenever `ox_fuel_assets` is updated. See `ox_fuel/README.md` for configuration, offset-editor instructions, credits, and licensing details.
