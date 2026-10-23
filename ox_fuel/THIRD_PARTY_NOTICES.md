# Third-Party Notices

## CDN-Fuel

Earlier builds redistributed selected assets from [CDN-Fuel](https://github.com/CodineDev/cdn-fuel), revision `edb6f5591f20803c844379eca4c3d78697e10cb1`. This historical attribution is retained.

CDN-Fuel is licensed under the GNU General Public License version 3. The complete GPL-3.0 text is included in this resource as `LICENSE`. These former, unmodified gas files were removed from the active beta during the dry-audio refresh:

- `assets/sounds/fuelstop.ogg`
- `assets/sounds/pickupnozzle.ogg`
- `assets/sounds/putbacknozzle.ogg`
- `assets/sounds/refuel.ogg`

Earlier beta builds also included CDN-Fuel's electric models and charging sounds; those are already removed. Charging, payment, occupancy, meter, synchronization, and cleanup code is independently implemented; CDN-Fuel runtime code is not included.

## Original DRS Sentinel Assets

The `drs_ev_*` station, connector, portable ground/carry pack, and docked cable models are original geometry. The connector preserves the previous mounting coordinate frame for compatibility, not its mesh. The unchanged `drs_ev_loop.ogg` and `drs_pack_loop.ogg` are original synthesized equipment loops, with no third-party audio samples. These contributions are distributed under this project's GPL-3.0 license. Reproducible Blender and loop builders are maintained in `ox_fuel/development/sentinel_ev_station`. The former synthesized one-shots are no longer shipped.

`drs_gas_pump_ron` and `drs_ron_hose_l` / `drs_ron_hose_r` are original style-A pump/hose geometry with project-supplied RON artwork. Editable Blender source and the reproducible builder are in `ox_fuel/development/ron_pump_model`.

The universal `drs_fuel_nozzle` is original DRS geometry and procedural material artwork under GPL-3.0, supplied by `ox_fuel_assets`. Its stock-compatible mounting frame preserves existing hand/vehicle offsets and hose endpoints; no stock GTA geometry or textures are redistributed. Reproducible source and validation are in `ox_fuel/development/fuel_nozzle`.

## LC Fuel

The 26 default electric charging station coordinates and original 18-model EV baseline were transcribed from [LC Fuel's public configuration](https://github.com/LeonardoSoares98/lc_fuel/blob/main/config.lua). The additional electric models from later GTA Online updates were researched and configured separately for ox_fuel Expanded.

`nozzle_offsets.lua` is adapted from the 669 active vehicle entries in LC Fuel v1.2.4's `Config.HiddenCustomVehicleParameters`, source revision [`d60dc59`](https://github.com/LeonardoSoares98/lc_fuel/tree/d60dc59). The data was moved into a standalone module and is consumed by ox_fuel Expanded's independently implemented hash cache, safe-bone resolver, fallback system, side handling, and debug generator. LC Fuel is licensed under GPL-3.0, whose complete text is included as `LICENSE`.

No LC Fuel runtime dependency is required. LC Fuel's runtime scripts, electric prop files, connector files, UI, and sounds are not redistributed by this resource.
## Original Gas Audio

The unchanged `drs_gas_loop.ogg` is original reproducible synthesis contributed under the resource's GPL-3.0 license, without third-party samples. Its builder is in `ox_fuel/development/ron_pump_model/polish`. The former gas one-shots have been replaced by the bank below.

## Recorded Foley Refresh

These audio assets retain their stated source licenses; they are not claimed as wholly original GPL recordings. No endorsement by the source authors is implied.

| Distributed file | Source and author | License |
| --- | --- | --- |
| `drs_holder_dock.ogg` | [replacing_gas_nozzle.wav](https://freesound.org/people/joedeshon/sounds/117420/) by joedeshon | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `drs_holder_release.ogg`, `drs_fuel_shutoff.ogg`, `drs_ev_unlock.ogg` | [Metallic latch release.wav](https://freesound.org/people/Crinkem/sounds/481789/) by Crinkem | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `drs_ev_lock.ogg` | [car seatbelt clicking.wav](https://freesound.org/people/RutgerMuller/sounds/50900/) by RutgerMuller | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `drs_equipment_relay.ogg` | [rotary_swich_relay.wav](https://freesound.org/people/xdrav/sounds/112844/) by xdrav | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `drs_fuel_contact.ogg`, `drs_pack_setdown.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) by Kenney: `impactMetal_light_000.ogg`, `impactSoft_heavy_000.ogg` | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

Modifications: selected transients/crops, mono downmix, fixed bandpass EQ, level adjustment, edge fades, resampling to 48 kHz, and Ogg Vorbis encoding. Freesound sources were obtained from the public high-quality previews. The fuel-contact and connector cues are adapted mechanical foley, not recordings of this custom hardware. The original recordings, provenance hashes, exact edit recipes, and reproducible builder are retained in `ox_fuel/development/audio_refresh`.

`drs_device_ready.ogg` and `drs_device_alert.ogg` are original, fixed-frequency device tones under GPL-3.0. They contain no third-party recordings or generated brush/sweep layers.
