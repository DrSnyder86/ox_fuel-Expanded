# ox_fuel Expanded Community Release Posts

Replace bracketed placeholders before publishing.

---

## Cfx.re Forum Post

### Title

**ox_fuel Expanded - Pumps, EV Charging, Physical Hoses, Live Registers, and Questionable Decisions**

### Short Description

An independent, free, GPL-3.0 community expansion of ox_fuel with physical nozzles, synchronized pumps, EV charging, portable power, realistic tank sizes, fuel grades, payment choices, positional audio, and model-specific pump interfaces.

### Post Body

ox_fuel went into the workshop for a hose adjustment and came back with an electrical charging network, a banking integration, 669 vehicle profiles, several custom interfaces, and a portable battery pack.

That was not the original plan. It is, however, the resource now.

**ox_fuel Expanded** is DrSnyder's independent community build based on [CommunityOx ox_fuel v1.5.2](https://github.com/CommunityOx/ox_fuel/tree/v1.5.2). It keeps the familiar `ox_fuel` export name for compatibility, then adds the systems that normally require several separate fuel resources and a long evening of explaining why the hose is underground.

This is not an official CommunityOx release. It is a free, source-available community collaboration assembled from the long-running ox_fuel lineage, adapted public LC Fuel configuration data, selected GPL-3.0 CDN-Fuel assets, and a substantial amount of new integration, synchronization, UI, transaction, debugging, and cleanup code.

#### The Lore-Friendly Explanation

Following an entirely preventable series of incidents involving running engines, stretched fuel hoses, unattended aircraft pumps, and one suspiciously enthusiastic golf cart owner, the San Andreas Bureau of Fueling Standards has issued new operating requirements.

Drivers may now be asked to select a grade, choose how they intend to pay, stand near the correct filler port, return borrowed equipment, and refrain from testing whether a gasoline pump can stop a moving vehicle.

The Bureau remains surprised that these rules were necessary.

#### What Is Included

- Physical fuel nozzles with configurable ropes, pump anchors, model-specific offsets, maximum range checks, vehicle attachment, carry animations, and complete cleanup.
- Automatic fuel-cap detection using `petrolcap`, fuel-tank bones, safe body fallbacks, and a hash-cached model override system.
- An in-game offset editor that places the real nozzle or EV connector, lets developers tune position and rotation, and prints ready-to-paste profiles.
- 669 LC Fuel-derived vehicle attachment profiles adapted into a standalone ox_fuel dataset with no LC Fuel runtime dependency.
- Synchronized occupancy so two players cannot quietly purchase the same gallon from the same pump at the same time.
- Regular 87 and Premium 93 fuel with separate prices, gallon-weighted blending, and configurable consumption benefits.
- Vehicle-class tank capacities and per-model consumption tuning instead of treating every motorcycle, sedan, aircraft, and commercial vehicle as the same container.
- Cash and bank payment with built-in Qbox, QBCore, and ESX support plus a custom provider hook.
- Server-authoritative fueling and charging sessions that validate distance, timing, selected product, payment method, balance, delivered fuel, and final cost.
- Custom modern and vintage pump interfaces with model-specific RON, LTD, XERO, and Globe Oil branding.
- Live sale and volume registers, tank percentage, pump state, price, grade, payment account, and final values held until the nozzle is returned.
- Functioning custom pump locations for docks, rooftops, airports, boats, and aircraft, including location-specific hose lengths.
- Scripted pump damage that removes custom props safely before creating the synchronized petrol-pump explosion.
- Full EV charging with physical connectors, thin black cables, synchronized station occupancy, Standard/Rapid charging, Cash/Bank payment, charging-station blips, positional audio, and a dedicated Sentinel terminal.
- Configurable EV capacities and consumption for the original LC Fuel baseline plus later GTA Online electric models.
- Electrical charger damage with cyan flashes, sparks, smoke, fault audio, intermittent arcing, and an optional nearby-player shock effect.
- A deployable 12 kWh portable EV power unit that can be purchased, carried, placed, targeted, discharged into a vehicle, damaged, picked back up, and recharged at a station.
- Positional pump and charger audio through `san_andreas_sound`, with managed loops that are explicitly stopped during completion, cancellation, lease loss, disconnect, or resource shutdown.
- A persistent `ox_fuel_assets` companion resource so the main fuel script can restart without live-unloading streamed EV archetypes.

#### Experimental Feature: Common Sense and Other Optional Hazards

The release includes an optional **Chaos Mode**. Its master switch is disabled by default. Serious roleplay servers can leave it alone. Servers that believe consequences build character can begin adjusting percentages.

The first experiment includes:

- Refueling with the engine running produces a warning and may stall the vehicle, start a temporary fire, or, at an extremely configurable rate, produce a much shorter refueling session than expected.
- Driving away with an attached nozzle breaks and cleans up the hose, then may damage the vehicle, start a fire, trigger an explosion, or destroy a resource-spawned custom pump.
- Configured old pump models may run slowly or click off briefly before resuming.
- Rapid charging may trip a charger protection fault with electrical effects, while the portable power unit may stop on a thermal warning.
- Every chance roll is made on the server, major events have per-player cooldowns, and a transfer charges only for fuel or energy already delivered.

These systems are opt-in server flavor, not hidden random punishment. Probabilities, effects, eligible pump types and charging modes, warnings, cooldowns, and administrative logging are configurable in `chaosMode`.

#### Compatibility and Installation

This build is designed as a replacement-minded ox_fuel fork and preserves the public `ox_fuel` event and export names. Keep the resource folder named `ox_fuel` unless you also update integrations that call it by name.

Requirements:

- `ox_lib`
- `ox_inventory`
- `ox_target`
- `san_andreas_sound`
- The included `ox_fuel_assets` companion resource

It is close to drag-and-drop, but it is not magic. Read the included installation steps, copy the supplied sounds to San Andreas Sound, install the optional portable charger item and image when desired, and review prices, pump locations, EV models, vehicle profiles, and framework settings before opening the station to the public.

#### Community Sources, Licensing, and Credit

This release exists because free community resources were available to study, adapt, and improve.

- Base resource: [CommunityOx ox_fuel v1.5.2](https://github.com/CommunityOx/ox_fuel/tree/v1.5.2)
- Selected EV models and sounds: [CDN-Fuel](https://github.com/CodineDev/cdn-fuel)
- Adapted vehicle offset data and configuration references: [LC Fuel](https://github.com/LeonardoSoares98/lc_fuel)

ox_fuel Expanded and its redistributed GPL components are provided under GPL-3.0. The package includes the complete license and a `THIRD_PARTY_NOTICES.md` file identifying third-party files, source revisions, modifications, and attribution. Free and source-available does not mean public domain; keep the license and notices with redistributed or modified copies.

No paid dependency, encrypted runtime, or LC Fuel runtime installation is required. This is a community release, not an official update from Overextended, CommunityOx, CDN-Fuel, or LC Fuel.

#### Links

- GitHub: [GITHUB URL]
- Documentation: [DOCUMENTATION URL]
- Preview video: [VIDEO URL]
- Support or discussion: [THREAD/DISCORD URL]

**Release status:** [BETA/RELEASE CANDIDATE/STABLE]

Please test unusual MLO pumps, addon vehicles, later game-build EVs, and framework payment adapters before deploying to a live economy. Bug reports are more useful with the vehicle spawn name, model hash, pump model, framework, reproduction steps, and a screenshot.

---

## Website Post

### Page Title

**ox_fuel Expanded: The Fuel Script That Refused to Stay a Fuel Script**

### Meta Description

Meet ox_fuel Expanded, DrSnyder's free GPL-3.0 FiveM community fuel system with physical hoses, EV charging, portable power, synchronized pumps, realistic tanks, branded interfaces, and years of open community work brought together.

### Hero Copy

**One fuel resource. Several community projects. Far too many correctly attached hoses.**

ox_fuel Expanded brings gasoline, premium grades, EV charging, portable power, positional sound, synchronized pumps, realistic vehicle capacities, and model-specific interfaces into one compatible community build.

### Article

There is a familiar kind of FiveM project that begins with one small sentence:

> The hose looks a little wrong.

Several development chapters later, the hose has model-specific anchors, a maximum range, automatic fuel-cap detection, a 669-vehicle compatibility dataset, an offset editor, synchronized occupancy, positional audio, server-authoritative billing, and a cleanup routine designed to survive nearly every creative decision a player can make.

That project is now **ox_fuel Expanded**.

Built by DrSnyder on the CommunityOx ox_fuel v1.5.2 foundation, this release brings together ideas and publicly available material from several respected free community fuel resources. LC Fuel's public configuration work helped establish vehicle offsets and charging locations. CDN-Fuel's GPL-3.0 electric models and sounds provide the physical charging equipment. The ox_fuel lineage preserves the compatibility and fuel-state behavior servers already know.

The rest is the integration work: new transaction sessions, payment adapters, occupancy synchronization, branded NUI displays, physical prop handling, safe scripted destruction, EV consumption, portable charging, debugging tools, restart cleanup, and the many small safeguards required to make all of those systems behave like one resource instead of several resources standing near each other.

#### A Brief History According to San Andreas

The San Andreas Bureau of Fueling Standards allegedly approved the system after learning that local drivers routinely:

- Leave engines running while refueling.
- Attempt to stretch a five-meter hose across an eight-meter parking decision.
- Treat gasoline pumps as collision-testing equipment.
- Bring jerry cans to electric vehicles.
- Bring electric connectors to vehicles the configuration has never heard of.
- Walk away with equipment that clearly belongs to the station.

The new system cannot improve judgment, but it can synchronize the pump, calculate the bill, find the filler port, stop the sound loop, and clean up the rope afterward.

#### Gasoline Without the Generic Progress Bar

Every supported pump can carry its own visual identity. RON, LTD, XERO, and Globe Oil pumps use modern or vintage register themes with matching logos and accents. Drivers choose Regular 87 or Premium 93 and pay with Cash or Bank directly on the pump display.

Vehicle classes receive different tank capacities, Premium is blended proportionally instead of magically upgrading a full tank, and pricing is calculated from actual configured gallons or liters. The final sale remains on the register until the nozzle is returned, because a pump that instantly forgets the transaction is not especially convincing.

#### Electric Charging That Belongs in the Same World

EV stations use physical connectors, thin charging cables, electrical sounds, configurable map blips, and a dedicated digital Sentinel interface. Charging speed, payment method, battery percentage, delivered energy, remaining time, and cost are all handled through server-authoritative sessions.

Damaged chargers spark, flash, smoke, arc, and shut down. They do not explode like gasoline pumps unless somebody deliberately changes the design philosophy and accepts responsibility for the results.

For drivers who manage to run out of charge away from a station, the optional portable power unit can be purchased, carried, deployed, connected to an EV, picked up, damaged, and recharged. Its discreet interface reports only the information needed to avoid turning emergency roadside power into another full-size dashboard.

#### Built for Real Servers, Including Strange Ones

ox_fuel Expanded supports synchronized custom pump locations for aircraft, boats, rooftops, docks, MLOs, and other places Rockstar did not furnish with a convenient working pump. Different locations can use longer hoses, while normal map pumps keep normal reach.

Automatic bone detection handles correctly modeled vehicles. Explicit profiles cover unusual models. Developers can aim at a filler port, open the offset editor, position the real prop, and print a ready-to-paste configuration instead of guessing six numbers and restarting the resource repeatedly.

#### Optional Chaos, Applied Responsibly

The included Chaos Mode adds individually configurable common-sense and satire settings. Refueling with a running engine can carry a configurable stall, fire, or explosion risk. Driving away with the nozzle attached can damage something more expensive than the player's dignity. Old pumps can occasionally behave like old pumps, Rapid chargers can trip protection faults, and portable packs can stop on a thermal warning.

Chaos Mode is off by default. Its chance rolls are server-side, serious results use configurable cooldowns, and interrupted sessions bill only what was delivered. The goal is controlled, logged, adjustable consequences, not hidden random explosions inside an ordinary fuel stop.

#### Free Community Work, Properly Credited

This release is free and source-available under GPL-3.0. It is an independent community fork, not an official CommunityOx release. The package includes its license and detailed third-party notices for the CommunityOx base, CDN-Fuel assets, and LC Fuel-derived data.

The lineage matters. These resources were shared so people could learn from them, adapt them, and keep building. ox_fuel Expanded is one more chapter in that process: years of community fuel-resource knowledge assembled into one practical replacement before the next Grand Theft Auto gives everyone an entirely new collection of parking-lot problems.

### Closing Callout

**Install it. Configure it. Test it with the weirdest vehicle on your server. Return the nozzle when finished.**

- Download: [GITHUB/RELEASE URL]
- Documentation: [DOCUMENTATION URL]
- Screenshots and video: [MEDIA URL]

### Optional Footer Joke

The San Andreas Bureau of Fueling Standards is fictional. Its disappointment is not.

---

## Suggested Visual Direction

Use a dark, lore-friendly service-station background rather than a generic blue technology gradient:

- Nighttime RON, LTD, XERO, or Globe Oil forecourt with the pump clearly visible.
- One gasoline vehicle and one EV in separate bays, with no real-world trademarks.
- Warm sodium-vapor canopy lighting, restrained cyan light near the EV charger, and wet pavement reflections.
- Leave the center-left or upper-left area visually quiet for the title.
- Keep hoses, connector, pump face, and charging station readable rather than blurred into atmosphere.
- Avoid explosions in the main release image; save those for the optional Chaos Mode section.

Suggested hero caption:

> **Fueling San Andreas, one properly returned nozzle at a time.**
