if not lib.checkDependency('ox_lib', '3.22.0', true) then return end
if not lib.checkDependency('ox_inventory', '2.30.0', true) then return end

return {
	-- Check the maintained GitHub package once when the server starts.
	versionCheck = {
		enabled = true,
		manifestUrl = 'https://raw.githubusercontent.com/DrSnyder86/ox_fuel-Expanded/main/ox_fuel/fxmanifest.lua',
		downloadUrl = 'https://github.com/DrSnyder86/ox_fuel-Expanded',
		notifyCurrent = false,
		verboseErrors = false,
		delayMs = 1500,
	},

	-- Enable support for ox_target
	ox_target = true,

	/*
	* Show or hide gas stations blips
	* 0 - Hide all
	* 1 - Show nearest (5000ms interval check)
	* 2 - Show all
	*/
	showBlips = 1,

	-- Fuel transfer update interval
	refillTick = 500,

	-- Volume-based fueling and pricing
	fueling = {
		pricePerGallon = 5.82,
		pumpGallonsPerSecond = 0.20,
		canGallonsPerSecond = 0.10,
		priceDecimals = 0, -- ox_inventory money items use whole currency units
		defaultGrade = 'regular',
		premiumGrade = 'premium',
		gradeOrder = { 'regular', 'premium' },
		grades = {
			regular = {
				label = 'Regular',
				shortLabel = 'REG',
				octane = 87,
				pricePerGallon = 5.82,
				premiumRatio = 0.0,
				consumptionMultiplier = 1.00,
			},
			premium = {
				label = 'Premium',
				shortLabel = 'PREM',
				octane = 93,
				pricePerGallon = 7.99,
				premiumRatio = 1.0,
				consumptionMultiplier = 0.90,
			},
		},
	},

	-- Player payment accounts. Bank support is auto-detected for Qbox, QBCore, and ESX.
	payments = {
		defaultMethod = 'cash',
		methodOrder = { 'cash', 'bank' },
		methods = {
			cash = { label = 'Cash', shortLabel = 'CASH', enabled = true },
			bank = { label = 'Bank', shortLabel = 'BANK', enabled = true },
		},
	},

	-- Server-side fueling validation
	serverValidation = {
		maxVehicleDistance = 6.0,
		sourceVehicleTolerance = 4.0, -- Accounts for the vehicle center being farther from the filler than the hose end
		tickTolerance = 2,
		sessionGraceMs = 10000,
	},

	-- Synchronize each physical pump handle. All models are dual-nozzle except configured exclusions.
	pumpOccupancy = {
		enabled = true,
		dualNozzles = true,
		sharedFlowMultiplier = 0.65,
		singleNozzleModels = {
			[`prop_vintage_pump`] = true,
		},
		coordinatePrecision = 10,
		maxAcquireDistance = 4.0,
		leaseDurationMs = 15000,
		heartbeatMs = 5000,
	},

	-- Optional experimental consequences. The server performs every chance roll.
	-- Keep the master switch disabled for normal community-release behavior.
	chaosMode = {
		enabled = false,
		adminLogging = true,
		protections = {
			playerCooldownSeconds = 900,
			oneMajorEventPerSession = true,
		},
		engineRunning = {
			enabled = true,
			warnPlayer = true,
			stallChance = 8.0,
			fireChance = 0.75,
			explosionChance = 0.10,
			fireDurationMs = 7000,
			engineDamage = 250.0,
			bodyDamage = 100.0,
			explosionType = 6,
			damageScale = 0.65,
			cameraShake = 0.5,
		},
		driveOff = {
			enabled = true,
			vehicleDamageChance = 35.0,
			pumpDamageChance = 20.0, -- Resource-spawned custom pumps only
			fireChance = 2.0,
			explosionChance = 0.25,
			engineDamage = 180.0,
			bodyDamage = 120.0,
			fireDurationMs = 6000,
			explosionType = 6,
			damageScale = 0.55,
			cameraShake = 0.45,
		},
		vintagePumpQuirks = {
			enabled = true,
			models = {
				`prop_gas_pump_old2`,
				`prop_vintage_pump`,
				`prop_gas_pump_old3`,
			},
			slowFlowChance = 4.0,
			flowMultiplier = 0.55,
			clickOffChance = 4.0,
			clickOffDurationMs = 1500,
			clickOffProgressMin = 0.35,
			clickOffProgressMax = 0.80,
		},
		rapidChargeFault = {
			enabled = true,
			modes = { rapid = true },
			shutdownChance = 3.0,
			progressMin = 0.35,
			progressMax = 0.80,
		},
		portableThermalShutdown = {
			enabled = true,
			shutdownChance = 4.0,
			progressMin = 0.35,
			progressMax = 0.85,
		},
	},

	-- Compact live meter with numeric tank/can level display
	fuelMeter = {
		enabled = true,
		checkout = 'nui', -- 'nui' for the pump/charger screen or 'ox_lib' for input dialogs
		lingerMs = 900,
		canLingerMs = 1800,
		currency = '$',
		unit = 'gallons', -- 'gallons' or 'liters'
		pumpDisplays = {
			[`drs_gas_pump_ron`] = { theme = 'modern', variant = 'ron-modern', brand = 'RON', logo = 'prop_gas_pump_1a', accent = '#ef8b32' },
			[`drs_ev_station`] = { theme = 'modern', variant = 'charge-modern', brand = 'SENTINEL EV CHARGING', logo = 'electric_charger', accent = '#19b9ff' },
			[`prop_gas_pump_old2`] = { theme = 'vintage', variant = 'xero-vintage', brand = 'XERO', logo = 'prop_gas_pump_old2', accent = '#47c4c7' },
			[`prop_gas_pump_1a`] = { theme = 'modern', variant = 'ron-modern', brand = 'RON', logo = 'prop_gas_pump_1a', accent = '#ef8b32' },
			[`prop_vintage_pump`] = { theme = 'vintage', variant = 'globe-vintage', brand = 'GLOBE OIL', logo = 'prop_vintage_pump', accent = '#d9584f' },
			[`prop_gas_pump_old3`] = { theme = 'vintage', variant = 'ltd-vintage', brand = 'LTD', logo = 'prop_gas_pump_old3', accent = '#d94f4f' },
			[`prop_gas_pump_1c`] = { theme = 'modern', variant = 'ltd-modern', brand = 'LTD', logo = 'prop_gas_pump_1c', accent = '#d94f4f' },
			[`prop_gas_pump_1b`] = { theme = 'modern', variant = 'globe-modern', brand = 'GLOBE OIL', logo = 'prop_gas_pump_1b', accent = '#d9584f' },
			[`prop_gas_pump_1d`] = { theme = 'modern', variant = 'xero-modern', brand = 'XERO', logo = 'prop_gas_pump_1d', accent = '#47c4c7' },
		},
	},

	-- Physical pump nozzle, hose, and San Andreas Sound positional audio
	nozzle = {
		enabled = true,
		model = `drs_fuel_nozzle`, -- Shared by every fuel pump; stock-compatible mount frame.
		hose = true,
		hoseLength = 5.0,
		hoseSlack = 0.45,
		ropeLength = 3.0,
		ropeMaxLength = 8.0,
		maxDistance = 7.5,
		ropeType = 1,
		debug = false,
		soundProvider = 'san_andreas_sound',
		soundBaseUrl = 'https://cfx-nui-san_andreas_sound/web/sounds/%s.ogg',
		soundMaxDistance = 18.0,
		soundAcousticClass = 'World',
		attachToFuelCap = true, -- Keep the nozzle attached until it is removed from the vehicle
		faceFuelCap = true,
		fuelCapDistance = 1.8,
		fuelCapDebug = false,
		fuelCapDebugDistance = 15.0,
		offsetDebug = {
			enabled = false,
			command = 'ox_fuel_nozzleoffset',
			connectorCommand = 'ox_fuel_chargeroffset',
			reportMissing = true,
			raycastDistance = 20.0,
			markerScale = 0.14,
		},
		fuelCapFallback = {
			enabled = true,
			attach = true,
			sidePadding = 0.18,
			heightScale = 0.48,
			rearQuarterScale = 0.25,
			middleScale = 0.48,
		},
		-- Legacy root-relative position overrides. Prefer complete profiles in nozzle_offsets.lua.
		fuelCapOffsets = {
			-- [`adder`] = { x = -1.05, y = -1.15, z = 0.45 },
			-- [`police`] = {
			-- 	{ x = -1.05, y = -1.20, z = 0.48 },
			-- 	{ x = 1.05, y = -1.20, z = 0.48 },
			-- },
		},
		-- Default adjustment for automatically detected fuel bones and body fallbacks.
		vehicleAttachOffset = { x = 0.0, y = -0.03, z = 0.02 },
		vehicleAttachRotation = { x = -90.0, y = 0.0, z = 0.0 },
		mirrorRightSide = true,
		rightSideRotationZ = 180.0,
		pumpHeight = 1.25,
		pumpEdgePadding = 0.10,
		pumpAnchorScale = 0.45,
		pumpOffsets = {
			[`prop_vintage_pump`] = { x = 0.0, y = 0.0, z = 0.0 },
			[`prop_gas_pump_1a`] = { x = 0.0, y = 0.0, z = 0.0 },
			[`prop_gas_pump_1b`] = { x = 0.0, y = 0.0, z = 0.0 },
			[`prop_gas_pump_1c`] = { x = 0.0, y = 0.0, z = 0.0 },
			[`prop_gas_pump_1d`] = { x = 0.0, y = 0.0, z = 0.0 },
			[`prop_gas_pump_old2`] = { x = 0.0, y = 0.0, z = 0.0 },
			[`prop_gas_pump_old3`] = { x = 0.0, y = 0.0, z = 0.0 },
		},
		-- Optional per-handle corrections applied after the automatic left/right anchor.
		pumpSlotOffsets = {
			-- [`prop_gas_pump_1a`] = {
			-- 	[1] = { x = 0.0, y = 0.0, z = 0.0 },
			-- 	[2] = { x = 0.0, y = 0.0, z = 0.0 },
			-- },
		},
		pumpHeights = {
			[`prop_gas_pump_1a`] = 1.35, -- RON
			[`prop_gas_pump_1b`] = 1.35, -- GLOBE OIL
			[`prop_gas_pump_1c`] = 1.35, -- LTD
			[`prop_gas_pump_1d`] = 1.35, -- XERO
			[`prop_gas_pump_old2`] = 1.25, -- XERO
			[`prop_gas_pump_old3`] = 1.25, -- LTD
			[`prop_vintage_pump`] = 1.10, -- GLOBE OIL
		},
		sounds = {
			pickup = { name = 'drs_holder_release', volume = 0.28, source = 'holder', maxDistance = 3.5 },
			putback = { name = 'drs_holder_dock', volume = 0.34, source = 'holder', maxDistance = 4.0 },
			start = { name = 'drs_equipment_relay', volume = 0.20, source = 'pump', maxDistance = 4.0 },
			pumpStop = { name = 'drs_equipment_relay', volume = 0.15, source = 'pump', maxDistance = 4.0 },
			connect = { name = 'drs_fuel_contact', volume = 0.22, source = 'nozzle', maxDistance = 3.0 },
			disconnect = { name = 'drs_fuel_contact', volume = 0.20, source = 'nozzle', maxDistance = 3.0 },
			refuel = { name = 'drs_gas_loop', volume = 0.24, source = 'nozzle', maxDistance = 18.0, loop = true, managed = true },
			stop = { name = 'drs_fuel_shutoff', volume = 0.34, source = 'nozzle', maxDistance = 4.0 },
			complete = false, -- The shutoff click already signals completion; no extra chime/click.
		},
		localResourceSounds = true,
	},

	-- Original illuminated RON replacement; other pump models/offsets remain unchanged.
	ronPump = {
		enabled = true, originalModel = `prop_gas_pump_1a`, model = `drs_gas_pump_ron`,
		spawnDistance = 140.0, despawnDistance = 180.0, maxNearby = 12, modelLodDistance = 180,
		headingOffset = 0.0, zOffset = 0.0, hideRadius = 0.10,
		damageable = true, reportDistance = 50.0,
		damageLocations = {}, -- Optional vec3 entries for RON pumps in unlisted MLO stations.
		stationDisplay = {
			enabled = true, model = `drs_gas_pump_ron`, mode = 'pump', hudFallback = false,
			useApproachSide = true, -- Either nozzle uses the register facing the player at pickup.
			renderDistance = 12.0, inputDistance = 3.5, textureWidth = 512, textureHeight = 384, minimumScreenPixels = 100,
			screens = {
				[1] = { x = 0.0, y = -0.2085, z = 1.23, width = 0.46, height = 0.345 },
				[2] = { x = 0.0, y = 0.2085, z = 1.23, width = 0.46, height = 0.345, back = true },
			},
		},
		docking = {
			enabled = true, model = `drs_gas_pump_ron`, renderDistance = 30.0, maxSources = 8,
			slots = {
				[1] = { offset = { x = -0.50, y = -0.035, z = 0.98 }, rotation = { x = 0.0, y = 0.0, z = -90.0 }, anchor = { x = -0.415, y = 0.0, z = 1.44 }, cableModel = `drs_ron_hose_l` },
				[2] = { offset = { x = 0.50, y = 0.035, z = 0.98 }, rotation = { x = 0.0, y = 0.0, z = 90.0 }, anchor = { x = 0.415, y = 0.0, z = 1.44 }, cableModel = `drs_ron_hose_r` },
			},
		},
		lighting = {
			enabled = false, -- RON now uses model-native night diffusers and an embedded light.
			model = `drs_gas_pump_ron`, nightOnly = true, renderDistance = 16.0,
			lights = {
				{ offset = { x = 0.0, y = -0.29, z = 1.59 }, span = { x = 0.62 }, samples = 3, colour = { r = 255, g = 175, b = 85 }, range = 0.42, intensity = 1.0 },
				{ offset = { x = 0.0, y = 0.29, z = 1.59 }, span = { x = 0.62 }, samples = 3, colour = { r = 255, g = 175, b = 85 }, range = 0.42, intensity = 1.0 },
				{ offset = { x = 0.0, y = -0.265, z = 0.10 }, span = { x = 0.60 }, samples = 3, colour = { r = 255, g = 154, b = 48 }, range = 0.40, intensity = 0.65 },
				{ offset = { x = 0.0, y = 0.265, z = 0.10 }, span = { x = 0.60 }, samples = 3, colour = { r = 255, g = 154, b = 48 }, range = 0.40, intensity = 0.65 },
			},
		},
	},
	-- Original DRS Sentinel hardware/audio; station coordinates adapted from LC Fuel.
	electric = {
		enabled = true,
		chargerModel = `drs_ev_station`,
		modelLodDistance = 180, -- Cabinet geometry only; DUI and light ranges stay close.
		stationDisplay = {
			enabled = true,
			hudFallback = false, -- Sentinel uses the cabinet screens only; gas/portable keep their HUD.
			model = `drs_ev_station`,
			renderDistance = 14.0,
			inputDistance = 3.0,
			minimumScreenPixels = 130, -- Readability threshold if hudFallback is enabled explicitly.
			maxStations = 2,
			textureWidth = 512,
			textureHeight = 640,
			screens = {
				[1] = { x = -0.18, y = -0.325, z = 1.34, width = 0.30, height = 0.375 },
				[2] = { x = 0.18, y = -0.325, z = 1.34, width = 0.30, height = 0.375 },
			},
		},
		connectorModel = `drs_ev_connector`,
		docking = {
			enabled = true,
			model = `drs_ev_station`,
			renderDistance = 30.0,
			maxSources = 4,
			slots = {
				[1] = { offset = { x = -0.473, y = -0.067, z = 1.27 }, rotation = { x = 0.0, y = 0.0, z = 90.0 }, cableModel = `drs_ev_cable_l` },
				[2] = { offset = { x = 0.473, y = -0.067, z = 1.27 }, rotation = { x = 0.0, y = 0.0, z = -90.0 }, cableModel = `drs_ev_cable_r` },
			},
		},
		stationLighting = {
			enabled = true,
			model = `drs_ev_station`,
			nightOnly = true,
			renderDistance = 16.0,
			maxSources = 2, -- Shared nearest-cabinet limit, at most 12 light samples per cabinet.
			lights = {
				{ offset = { x = 0.0, y = -0.31, z = 1.91 }, span = { x = 0.54 }, samples = 3, colour = { r = 36, g = 190, b = 213 }, range = 0.38, intensity = 1.10 },
				{ offset = { x = 0.0, y = -0.33, z = 0.44 }, span = { x = 0.54 }, samples = 3, colour = { r = 185, g = 44, b = 102 }, range = 0.32, intensity = 0.75 },
				{ offset = { x = -0.18, y = -0.32, z = 1.035 }, colour = { r = 36, g = 190, b = 213 }, range = 0.22, intensity = 0.55 },
				{ offset = { x = 0.18, y = -0.32, z = 1.035 }, colour = { r = 36, g = 190, b = 213 }, range = 0.22, intensity = 0.55 },
			},
		},
		headingOffset = 180.0,
		showBlips = 1, -- 0 = hidden, 1 = nearby, 2 = all
		blip = {
			sprite = 620, -- Vehicle with an electric bolt
			colour = 3,
			scale = 0.55,
			display = 4,
			shortRange = true,
			nearbyDistance = 60.0,
		},
		damageEffects = {
			enabled = true,
			damageable = true,
			synchronize = true,
			reportDistance = 100.0,
			renderDistance = 125.0,
			weaponImpacts = true,
			weaponImpactRadius = 1.5,
			vehicleImpacts = true,
			vehicleImpactDistance = 3.0,
			vehicleImpactHeight = 2.25,
			vehicleImpactSpeed = 6.0,
			vehicleApproachDot = 0.6,
			flash = {
				durationMs = 850,
				range = 7.0,
				intensity = 12.0,
				colour = { r = 23, g = 192, b = 235 },
			},
			sparks = {
				asset = 'core',
				name = 'ent_sht_electrical_box',
				offset = { x = 0.0, y = 0.0, z = 1.25 },
				scale = 0.85,
				burstCount = 3,
				intervalMinMs = 2500,
				intervalMaxMs = 6000,
			},
			smoke = {
				asset = 'core',
				name = 'ent_amb_smoke_foundry',
				offset = { x = 0.0, y = 0.0, z = 1.15 },
				scale = 0.18,
				durationMs = 45000,
			},
			playerShock = false,
			shockRadius = 2.0,
			shockDamage = 5,
			shockRagdollMs = 1000,
		},
		cable = true,
		cableLength = 3.0,
		cableMaxLength = 7.5,
		cableSlack = 0.45,
		maxDistance = 7.5,
		ropeType = 4, -- Very thin black cable
		chargePortDistance = 1.8,
		faceChargePort = true,
		attachToChargePort = true, -- Keep the connector attached until it is removed from the vehicle
		vehicleAttachOffset = { x = 0.0, y = 0.0, z = 0.0 },
		-- Connector correction for EVs without an imported/model-specific nozzle profile.
		-- Positive X moves a left-side mount inward and is mirrored for a right-side port.
		automaticVehicleAttachOffset = { x = 0.09, y = 0.0, z = 0.0 },
		automaticVehicleAttachRotation = { x = 20.0, y = -45.0, z = -90.0 },
		mirrorRightSide = true,
		rightSideRotationZ = 180.0,
		-- Final correction added to every resolved electric connector rotation.
		vehicleAttachRotation = { x = 0.0, y = 45.0, z = 180.0 },
		chargerCableOffset = { x = 0.0, y = -0.035, z = 1.10 },
		chargerCableSlotOffsets = {
			[1] = { x = -0.46, y = 0.0, z = 0.0 },
			[2] = { x = 0.46, y = 0.0, z = 0.0 },
		},
		connectorCableOffset = { x = -0.005, y = 0.185, z = -0.05 },
		handOffset = { x = 0.24, y = 0.10, z = -0.052 },
		handRotation = { x = -45.0, y = 120.0, z = 75.0 },
		soundProvider = 'san_andreas_sound',
		localResourceSounds = true, -- Original EV clips are served directly by ox_fuel.
		soundMaxDistance = 18.0,
		soundAcousticClass = 'World',
		sounds = {
			chargePickup = { name = 'drs_holder_release', volume = 0.26, source = 'holder', maxDistance = 3.5 },
			chargePutback = { name = 'drs_holder_dock', volume = 0.26, source = 'holder', maxDistance = 4.0 },
			chargeConnect = { name = 'drs_ev_lock', volume = 0.32, source = 'connector', maxDistance = 3.0 },
			chargeDisconnect = { name = 'drs_ev_unlock', volume = 0.28, source = 'connector', maxDistance = 3.0 },
			chargeStart = { name = 'drs_equipment_relay', volume = 0.30, source = 'charger', maxDistance = 4.0 },
			chargeLoop = { name = 'drs_ev_loop', volume = 0.30, source = 'charger', maxDistance = 12.0, loop = true, managed = true },
			chargeStop = { name = 'drs_equipment_relay', volume = 0.24, source = 'charger', maxDistance = 4.0 },
			chargeComplete = { name = 'drs_device_ready', volume = 0.24, source = 'charger', maxDistance = 6.0 },
			chargeFault = { name = 'drs_device_alert', volume = 0.34, source = 'charger', maxDistance = 8.0 },
			portableChargePickup = { name = 'drs_holder_release', volume = 0.20, source = 'holder', maxDistance = 2.5 },
			portableChargePutback = { name = 'drs_holder_dock', volume = 0.20, source = 'holder', maxDistance = 3.0 },
			portableChargeConnect = { name = 'drs_ev_lock', volume = 0.26, source = 'connector', maxDistance = 3.0 },
			portableChargeDisconnect = { name = 'drs_ev_unlock', volume = 0.23, source = 'connector', maxDistance = 3.0 },
			portableChargeStart = { name = 'drs_equipment_relay', volume = 0.18, source = 'charger', maxDistance = 3.0 },
			portableChargeLoop = { name = 'drs_pack_loop', volume = 0.25, source = 'charger', maxDistance = 7.0, loop = true, managed = true },
			portableChargeStop = { name = 'drs_equipment_relay', volume = 0.15, source = 'charger', maxDistance = 3.0 },
			portableChargeComplete = { name = 'drs_device_ready', volume = 0.18, source = 'charger', maxDistance = 4.0 },
			portableChargeFault = { name = 'drs_device_alert', volume = 0.28, source = 'charger', maxDistance = 6.0 },
			portableDeploy = { name = 'drs_pack_setdown', volume = 0.32, source = 'charger', maxDistance = 3.5 },
			portableLift = { name = 'drs_holder_release', volume = 0.16, source = 'charger', maxDistance = 2.5 },
		},
		defaultMode = 'standard',
		modeOrder = { 'standard', 'rapid' },
		modes = {
			standard = { label = 'Standard', shortLabel = 'STD', pricePerKwh = 0.52, kwhPerSecond = 0.55, displayPowerKw = 150 },
			rapid = { label = 'Rapid', shortLabel = 'RAPID', pricePerKwh = 0.72, kwhPerSecond = 0.85, displayPowerKw = 250 },
		},
		-- Deployable emergency battery pack. Add the item definition from
		-- install/ox_inventory_items.lua to ox_inventory before enabling it in game.
		portable = {
			enabled = true,
			itemName = 'portable_ev_charger',
			capacityKwh = 12.0,
			outputKwhPerSecond = 0.20,
			displayPowerKw = 7.2,
			purchaseEnabled = true,
			purchasePrice = 2500.0,
			purchaseDuration = 4500,
			groundModel = `drs_ev_pack`,
			carryModel = `drs_ev_pack_carry`,
			docking = {
				enabled = true,
				offset = { x = 0.13, y = -0.142, z = 0.14 },
				rotation = { x = 0.0, y = 0.0, z = 180.0 },
				cableModel = `drs_ev_pack_cable`,
			},
			deployDistance = 1.05,
			deployHeadingOffset = 0.0,
			targetRadius = 0.85,
			interactionDistance = 2.5,
			pickupDistance = 3.0,
			rechargeDistance = 3.0,
			cableLength = 2.0,
			cableMaxLength = 5.0,
			cableSlack = 0.30,
			cableOffset = { x = -0.13, y = -0.141, z = 0.12 },
			carryOffset = { x = 0.12, y = 0.02, z = -0.02 },
			carryRotation = { x = -85.0, y = 15.0, z = 15.0 },
			interface = {
				warningBeeps = true,
				lowBatteryPercent = 20.0,
				criticalBatteryPercent = 10.0,
				lowBatteryBeepIntervalMs = 7500,
				criticalBatteryBeepIntervalMs = 3500,
				warningBeepVolume = 0.08,
			},
			placementAnimation = {
				dictionary = 'pickup_object',
				clip = 'pickup_low',
				durationMs = 950,
			},
			damageEffects = {
				enabled = true,
				reportDistance = 20.0,
					weaponImpacts = true,
				weaponImpactRadius = 1.0,
				vehicleImpacts = true,
				vehicleImpactDistance = 2.0,
				vehicleImpactHeight = 1.5,
				vehicleImpactSpeed = 4.0,
				vehicleApproachDot = 0.5,
				effectOffset = { x = 0.0, y = 0.0, z = -0.98 },
			},
		},
		defaultBatteryCapacityKwh = 75.0,
		-- Base battery percentage drained each second before model load/RPM/speed multipliers.
		consumptionPercentPerSecond = 0.025,
		vehicles = {
			[`voltic`] = { batteryCapacityKwh = 53.0, consumptionRate = 1.02 },
			[`voltic2`] = { batteryCapacityKwh = 60.0, consumptionRate = 1.08 },
			[`caddy`] = { batteryCapacityKwh = 12.0, consumptionRate = 0.92 },
			[`caddy2`] = { batteryCapacityKwh = 12.0, consumptionRate = 0.92 },
			[`caddy3`] = { batteryCapacityKwh = 15.0, consumptionRate = 0.94 },
			[`surge`] = { batteryCapacityKwh = 65.0, consumptionRate = 0.98 },
			[`iwagen`] = { batteryCapacityKwh = 95.0, consumptionRate = 1.06 },
			[`raiden`] = { batteryCapacityKwh = 90.0, consumptionRate = 1.01 },
			[`airtug`] = { batteryCapacityKwh = 24.0, consumptionRate = 0.95 },
			[`neon`] = { batteryCapacityKwh = 90.0, consumptionRate = 1.04 },
			[`omnisegt`] = { batteryCapacityKwh = 85.0, consumptionRate = 1.03 },
			[`cyclone`] = { batteryCapacityKwh = 70.0, consumptionRate = 1.08 },
			[`tezeract`] = { batteryCapacityKwh = 90.0, consumptionRate = 1.06 },
			[`rcbandito`] = { batteryCapacityKwh = 2.5, consumptionRate = 0.90 },
			[`imorgon`] = { batteryCapacityKwh = 80.0, consumptionRate = 1.02 },
			[`dilettante`] = { batteryCapacityKwh = 24.0, consumptionRate = 0.94 },
			[`dilettante2`] = { batteryCapacityKwh = 24.0, consumptionRate = 0.94 },
			[`khamelion`] = { batteryCapacityKwh = 65.0, consumptionRate = 1.00 },

			-- Electric vehicles added in later GTA Online updates.
			[`powersurge`] = { batteryCapacityKwh = 15.0, consumptionRate = 0.96 },
			[`cyclone2`] = { batteryCapacityKwh = 70.0, consumptionRate = 1.08 },
			[`virtue`] = { batteryCapacityKwh = 70.0, consumptionRate = 1.07 },
			[`buffalo5`] = { batteryCapacityKwh = 105.0, consumptionRate = 1.10 },
			[`lacoureuse`] = { batteryCapacityKwh = 70.0, consumptionRate = 0.99 },
			[`envisage`] = { batteryCapacityKwh = 85.0, consumptionRate = 1.03 },
			[`pipistrello`] = { batteryCapacityKwh = 90.0, consumptionRate = 1.07 },

			-- Later-build entries: Suzume needs 3570+, X-Treme/Vivanite2 need 3751+,
			-- and E-Stride needs a build containing the Kortz Center Heist assets.
			[`suzume`] = { batteryCapacityKwh = 70.0, consumptionRate = 1.08 },
			[`xtreme`] = { batteryCapacityKwh = 90.0, consumptionRate = 1.08 },
			[`vivanite2`] = { batteryCapacityKwh = 100.0, consumptionRate = 1.05 },
			[`estride`] = { batteryCapacityKwh = 90.0, consumptionRate = 1.04 },
		},
		chargerLocations = {
			{ location = vector4(175.9, -1546.65, 28.26, 225.29) },
			{ location = vector4(-51.09, -1767.02, 28.26, 48.16) },
			{ location = vector4(-514.06, -1216.25, 17.46, 67.29) },
			{ location = vector4(-704.64, -935.71, 18.21, 91.02) },
			{ location = vector4(279.79, -1237.35, 28.35, 182.07) },
			{ location = vector4(834.27, -1028.7, 26.16, 89.39) },
			{ location = vector4(1194.41, -1394.44, 34.37, 271.3) },
			{ location = vector4(1168.38, -323.56, 68.3, 281.22) },
			{ location = vector4(633.64, 247.22, 102.3, 61.29) },
			{ location = vector4(-1420.51, -278.76, 45.26, 138.35) },
			{ location = vector4(-2080.61, -338.52, 12.26, 353.21) },
			{ location = vector4(-98.12, 6403.39, 30.64, 142.49) },
			{ location = vector4(181.14, 6636.17, 30.61, 180.96) },
			{ location = vector4(1714.14, 6425.44, 31.79, 156.94) },
			{ location = vector4(1703.57, 4937.23, 41.08, 56.74) },
			{ location = vector4(1994.54, 3778.44, 31.18, 216.25) },
			{ location = vector4(1770.86, 3337.97, 40.43, 302.1) },
			{ location = vector4(2690.25, 3265.62, 54.24, 59.98) },
			{ location = vector4(1033.32, 2662.91, 38.55, 96.38) },
			{ location = vector4(267.96, 2599.47, 43.69, 6.8) },
			{ location = vector4(50.21, 2787.38, 56.88, 148.2) },
			{ location = vector4(-2570.04, 2317.1, 32.22, 22.29) },
			{ location = vector4(2545.81, 2586.18, 36.94, 84.74) },
			{ location = vector4(2561.24, 357.3, 107.62, 267.65) },
			{ location = vector4(-1819.22, 798.51, 137.16, 316.13) },
			{ location = vector4(-341.63, -1459.39, 29.76, 272.73) },
		},
	},

	-- Enables fuel can
	petrolCan = {
		enabled = true,
		duration = 10000,
		capacityGallons = 5.3,
		priceFromFuelVolume = true, -- Missing gallons use the selected grade's live price
		containerPrice = 20.0, -- Added only when purchasing a new can
		price = 51, -- Flat purchase fallback when priceFromFuelVolume is disabled
		refillPrice = 31, -- Full Regular refill fallback when priceFromFuelVolume is disabled
	},

	---Modifies the fuel consumption rate of all vehicles - see [`SET_FUEL_CONSUMPTION_RATE_MULTIPLIER`](https://docs.fivem.net/natives/?_0x845F3E5C).
	globalFuelConsumptionRate = 5.0,

	-- Tank capacities are US gallons. Consumption rates multiply the global rate above.
	vehicleProfiles = {
		default = { tankCapacityGallons = 20.0, consumptionRate = 1.00 },
		classes = {
			[0] = { name = 'Compacts', tankCapacityGallons = 12.0, consumptionRate = 0.92 },
			[1] = { name = 'Sedans', tankCapacityGallons = 20.0, consumptionRate = 1.00 },
			[2] = { name = 'SUVs', tankCapacityGallons = 30.0, consumptionRate = 1.08 },
			[3] = { name = 'Coupes', tankCapacityGallons = 18.0, consumptionRate = 0.98 },
			[4] = { name = 'Muscle', tankCapacityGallons = 22.0, consumptionRate = 1.10 },
			[5] = { name = 'Sports Classics', tankCapacityGallons = 20.0, consumptionRate = 1.02 },
			[6] = { name = 'Sports', tankCapacityGallons = 18.0, consumptionRate = 1.08 },
			[7] = { name = 'Super', tankCapacityGallons = 20.0, consumptionRate = 1.12 },
			[8] = { name = 'Motorcycles', tankCapacityGallons = 5.0, consumptionRate = 0.88 },
			[9] = { name = 'Off-road', tankCapacityGallons = 28.0, consumptionRate = 1.10 },
			[10] = { name = 'Industrial', tankCapacityGallons = 50.0, consumptionRate = 1.14 },
			[11] = { name = 'Utility', tankCapacityGallons = 40.0, consumptionRate = 1.07 },
			[12] = { name = 'Vans', tankCapacityGallons = 28.0, consumptionRate = 1.05 },
			[13] = { name = 'Cycles', tankCapacityGallons = 0.0, consumptionRate = 0.00 },
			[14] = { name = 'Boats', tankCapacityGallons = 35.0, consumptionRate = 1.08 },
			[15] = { name = 'Helicopters', tankCapacityGallons = 45.0, consumptionRate = 1.12 },
			[16] = { name = 'Planes', tankCapacityGallons = 60.0, consumptionRate = 1.15 },
			[17] = { name = 'Service', tankCapacityGallons = 35.0, consumptionRate = 1.04 },
			[18] = { name = 'Emergency', tankCapacityGallons = 25.0, consumptionRate = 1.10 },
			[19] = { name = 'Military', tankCapacityGallons = 50.0, consumptionRate = 1.15 },
			[20] = { name = 'Commercial', tankCapacityGallons = 60.0, consumptionRate = 1.15 },
			[21] = { name = 'Trains', tankCapacityGallons = 55.0, consumptionRate = 1.10 },
			[22] = { name = 'Open Wheel', tankCapacityGallons = 18.0, consumptionRate = 1.12 },
		},
		models = {
			-- [`bison`] = { tankCapacityGallons = 32.0, consumptionRate = 1.06 },
		},
	},

	-- Resource-spawned pumps remain invincible fixtures; scripted impacts safely synchronize destruction.
	customGasPumpProps = {
		damageable = true,
		synchronizeExplosions = true,
		reportDistance = 100.0,
		weaponImpacts = true,
		weaponImpactRadius = 1.5,
		vehicleImpacts = true,
		vehicleImpactDistance = 3.0,
		vehicleImpactHeight = 2.25,
		vehicleImpactSpeed = 6.0,
		vehicleApproachDot = 0.6,
		explosionType = 9, -- GTA petrol-pump explosion
		damageScale = 1.0,
		cameraShake = 1.0,
	},

	-- Custom static pumps. ropeLength overrides the maximum hose reach for that pump.
	customGasPumpLocations = {
		{ prop = 'prop_gas_pump_old3', location = vector4(442.2, -977.17, 42.69, 270.3), ropeLength = 14.0 }, -- MRPD Heli
		{ prop = 'prop_gas_pump_old3', location = vector4(362.65, -592.64, 73.16, 71.26), ropeLength = 14.0 }, -- Pillbox Heli
		{ prop = 'prop_gas_pump_old2', location = vector4(301.12, -1465.61, 45.51, 321.3), ropeLength = 14.0 }, -- Davis Medical Heli
		{ prop = 'prop_gas_pump_old2', location = vector4(-923.12, -2976.81, 12.95, 149.55), ropeLength = 14.0 }, -- LSIA Devin Weston Hangar
		{ prop = 'prop_gas_pump_old2', location = vector4(-1665.44, -3104.53, 12.94, 329.89), ropeLength = 14.0 }, -- LSIA Pegasus Hangar
		--{ prop = 'prop_gas_pump_1b', location = vector4(-706.13, -1464.14, 4.04, 320.0), ropeLength = 14.0 }, -- la puerta heli
		--{ prop = 'prop_gas_pump_1b', location = vector4(-764.81, -1434.32, 4.06, 320.0), ropeLength = 14.0 },
		{ prop = 'prop_gas_pump_old2', location = vector4(-775.95, -1433.55, 0.6, 231.25), ropeLength = 14.0 }, -- Puerto Del Sol
		{ prop = 'prop_gas_pump_old3', location = vector4(-2148.8, 3283.99, 31.81, 240.0), ropeLength = 14.0 }, -- Zancudo Hangar A1
		{ prop = 'prop_gas_pump_old2', location = vector4(-486.22, 5977.65, 30.3, 315.4), ropeLength = 14.0 }, -- Paleto PD Heli
		{ prop = 'prop_gas_pump_old2', location = vector4(2101.82, 4776.8, 40.02, 21.41), ropeLength = 14.0 }, -- McKenzie Field
		{ prop = 'prop_gas_pump_old2', location = vector4(1338.13, 4269.62, 30.5, 85.0), ropeLength = 14.0 }, -- Millars Boathouse
		{ prop = 'prop_gas_pump_old2', location = vector4(-1089.72, -830.6, 36.68, 129.0), ropeLength = 14.0 }, -- Vespucci PD Heli
		{ prop = 'prop_gas_pump_old2', location = vector4(483.28, -3382.83, 5.07, 0.0), ropeLength = 14.0 }, -- Merryweather Dock
		{ prop = 'prop_gas_pump_old2', location = vector4(-1158.29, -2848.67, 12.95, 240.0), ropeLength = 14.0 }, -- LSIA Heli
		{ prop = 'prop_gas_pump_old3', location = vector4(-1125.15, -2866.97, 12.95, 240.0), ropeLength = 14.0 }, -- LSIA Heli
		{ prop = 'prop_gas_pump_old3', location = vector4(1771.81, 3229.24, 41.51, 15.0), ropeLength = 14.0 }, -- Sandy Heli
		{ prop = 'prop_gas_pump_old2', location = vector4(1748.31, 3297.08, 40.16, 15.0), ropeLength = 14.0 }, -- Sandy Air
	},

	-- Gas pump models. Every custom pump prop must also be listed here.
	pumpModels = {
		`drs_gas_pump_ron`, -- Original RON style-A replacement
		`prop_gas_pump_old2`, -- XERO
		`prop_gas_pump_1a`, -- RON
		`prop_vintage_pump`, -- GLOBE OIL
		`prop_gas_pump_old3`, -- LTD
		`prop_gas_pump_1c`, -- LTD
		`prop_gas_pump_1b`, -- GLOBE OIL
		`prop_gas_pump_1d`, -- XERO
	}
}
