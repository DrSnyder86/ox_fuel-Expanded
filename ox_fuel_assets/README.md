# ox_fuel Assets

Original DRS Sentinel station, connector, portable pack, and docked cable models, plus the illuminated RON style-A pump, two idle hoses, and universal fuel nozzle for the ox_fuel Expanded beta. All eleven archetypes use the `drs_` prefix.

Keep this folder named `ox_fuel_assets`, start it before `ox_fuel`, and leave it running when restarting `ox_fuel`. Live YTYP unloading can crash connected clients.

Version 1.2.6 adds only `drs_fuel_nozzle`, the original unbranded forecourt/industrial fuel nozzle shared by all gas pumps. Its stock-compatible local frame keeps the hand, vehicle profiles, RON holders, and hose endpoint unchanged. It has three embedded material sets, three distance LODs, no lights, and no new runtime threads. Install the matching beta nozzle-model setting during a full server/client restart. Existing station, cabinet, connector, pack, and hose models are unchanged.

Install model updates during a full server/client restart, including the migration from `snyder_` or CDN models. Legacy charging props are not included in this beta.

Version 1.2.5 refines only the RON cabinet: control fascias sit almost flush with the posts, amber inserts form continuous rounded loops, and two outward-angled underside diffusers replace the hidden center panel. The slim white header edge is removed. Grade faces and keypad legends are softly backlit; Diesel is cosmetic and model-only. Two short-range native underside lights have no shadows, coronas, or volumetrics. RON scripted lights remain disabled. Accepted height/footprint, docks, collision, 180 m distant LODs, all hose models, and Sentinel assets are unchanged. Install the matching beta display-depth configuration and model updates together, only during a full server/client restart.

Licensed under GPL-3.0. Original Blender builders, editable source, and validation tools are maintained in `ox_fuel/development/sentinel_ev_station`, `ox_fuel/development/ron_pump_model/cabinet_controls`, and `ox_fuel/development/fuel_nozzle`, with earlier RON passes retained alongside them. See `LICENSE` and `THIRD_PARTY_NOTICES.md`.
