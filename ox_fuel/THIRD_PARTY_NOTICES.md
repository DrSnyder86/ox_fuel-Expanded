# Third-Party Notices

## CDN-Fuel

This resource redistributes selected assets from [CDN-Fuel](https://github.com/CodineDev/cdn-fuel), revision `edb6f5591f20803c844379eca4c3d78697e10cb1`.

CDN-Fuel is licensed under the GNU General Public License version 3. The complete GPL-3.0 text is included in this resource as `LICENSE`. The listed files are redistributed without modification:

- `ox_fuel_assets/stream/[electric_charger]/electric_charger.ydr`
- `ox_fuel_assets/stream/[electric_charger]/electric_charger_typ.ytyp`
- `ox_fuel_assets/stream/[electric_nozzle]/electric_nozzle.ydr`
- `ox_fuel_assets/stream/[electric_nozzle]/electric_nozzle_typ.ytyp`
- `assets/sounds/charging.ogg`
- `assets/sounds/chargestop.ogg`
- `assets/sounds/fuelstop.ogg`
- `assets/sounds/pickupnozzle.ogg`
- `assets/sounds/putbackcharger.ogg`
- `assets/sounds/putbacknozzle.ogg`
- `assets/sounds/refuel.ogg`

The EV models and sounds first appear together in CDN-Fuel commit `74b898a9aaff698e397d617b029182ffa843b7eb` dated 2022-12-26. ox_fuel Expanded's charging, payment, occupancy, meter, state synchronization, and cleanup code is a separate implementation written for this resource; CDN-Fuel runtime code is not included.

## LC Fuel

The 26 default electric charging station coordinates and original 18-model EV baseline were transcribed from [LC Fuel's public configuration](https://github.com/LeonardoSoares98/lc_fuel/blob/main/config.lua). The additional electric models from later GTA Online updates were researched and configured separately for ox_fuel Expanded.

`nozzle_offsets.lua` is adapted from the 669 active vehicle entries in LC Fuel v1.2.4's `Config.HiddenCustomVehicleParameters`, source revision [`d60dc59`](https://github.com/LeonardoSoares98/lc_fuel/tree/d60dc59). The data was moved into a standalone module and is consumed by ox_fuel Expanded's independently implemented hash cache, safe-bone resolver, fallback system, side handling, and debug generator. LC Fuel is licensed under GPL-3.0, whose complete text is included as `LICENSE`.

No LC Fuel runtime dependency is required. LC Fuel's runtime scripts, electric prop files, connector files, UI, and sounds are not redistributed by this resource.
