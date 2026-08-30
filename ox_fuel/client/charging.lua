local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local meter = require 'client.meter'
local checkout = require 'client.checkout'
local chargers = require 'client.chargers'
local propImpacts = require 'client.prop_impacts'
local electricProfiles = require 'electric_profiles'

local settings = config.electric or {}
local portableSettings = settings.portable or {}
local occupancySettings = config.pumpOccupancy or {}
local fuelingSettings = config.fueling or {}
local charging = {}

local connectorObject
local sourceCharger
local attachedVehicle
local cable
local cableChargerPosition
local cableMaxLength
local cablePinnedVertex
local ownsCableTextures = false
local chargingActive = false
local chargingSelection
local selectingOptions = false
local activeSessionId
local activeSessionType
local chargingRun = 0
local pumpLease
local occupiedChargers = {}
local soundCounter = 0
local activeSounds = {}
local sourceType
local portablePack
local portableRechargeActive = false
local portableRechargeSessionId
local portablePurchaseSessionId

local portableTargetNames = {
	'ox_fuel:portableTakeConnector',
	'ox_fuel:portableReturnConnector',
	'ox_fuel:portablePickup',
	'ox_fuel:portableStatus',
}

local function roundPrice(value)
	value = math.max(tonumber(value) or 0, 0)

	local decimals = math.clamp(math.floor(tonumber(fuelingSettings.priceDecimals) or 0), 0, 2)
	local scale = 10 ^ decimals
	local rounded = math.floor(value * scale + 0.5) / scale

	return value > 0 and math.max(rounded, 1 / scale) or 0
end

local function quantizeCoordinate(value)
	local precision = math.max(math.floor(tonumber(occupancySettings.coordinatePrecision) or 10), 1)
	local scaled = value * precision

	return scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)
end

local function getChargerIdentity(charger)
	if not charger or not DoesEntityExist(charger) then return end

	local model = GetEntityModel(charger)
	local coords = GetEntityCoords(charger)
	local key = ('%s:%s:%s:%s'):format(
		model,
		quantizeCoordinate(coords.x),
		quantizeCoordinate(coords.y),
		quantizeCoordinate(coords.z)
	)

	return key, model, { x = coords.x, y = coords.y, z = coords.z }
end

local function acquireChargerLease(charger)
	if occupancySettings.enabled == false then return true end

	local key, model, position = getChargerIdentity(charger)

	if not key then return false end

	local lease = lib.callback.await('ox_fuel:acquirePump', false, model, position)

	if not lease then return false end
	if lease.disabled then return true end

	pumpLease = lease
	occupiedChargers[lease.key] = lease.owner or GetPlayerServerId(PlayerId())

	return true
end

local function releaseChargerLease()
	local lease = pumpLease
	pumpLease = nil

	if not lease then return end

	occupiedChargers[lease.key] = nil
	TriggerServerEvent('ox_fuel:releasePump', lease.key, lease.token)
end

RegisterNetEvent('ox_fuel:pumpOccupancyChanged', function(key, owner)
	if type(key) ~= 'string' then return end

	occupiedChargers[key] = owner or nil
end)

CreateThread(function()
	if occupancySettings.enabled == false then return end

	Wait(500)

	local snapshot = lib.callback.await('ox_fuel:getPumpOccupancy', false)

	if type(snapshot) == 'table' then
		occupiedChargers = snapshot
	end
end)

local function soundProviderAvailable()
	if settings.soundProvider == 'interact-sound' then
		return GetResourceState('interact-sound') == 'started'
	end

	return GetResourceState('san_andreas_sound') == 'started'
end

local function networkIdForEntity(entity)
	if not entity or entity == 0 or not DoesEntityExist(entity) then return end
	if type(NetworkGetEntityIsNetworked) == 'function' and not NetworkGetEntityIsNetworked(entity) then return end

	local netId = NetworkGetNetworkIdFromEntity(entity)

	return netId and netId > 0 and netId or nil
end

local function ensureNetworked(entity)
	if not entity or entity == 0 or not DoesEntityExist(entity) then return end
	if type(NetworkGetEntityIsNetworked) == 'function' and NetworkGetEntityIsNetworked(entity) then return end
	if type(NetworkRegisterEntityAsNetworked) == 'function' then NetworkRegisterEntityAsNetworked(entity) end
end

local function soundId(soundName)
	local id = activeSounds[soundName]

	if id then return id end

	soundCounter = soundCounter + 1
		id = ('ox_fuel_expanded:%s:%s:%s'):format(GetPlayerServerId(PlayerId()), soundName, soundCounter)
	activeSounds[soundName] = id

	return id
end

local function soundPayload(sound, options)
	options = options or {}

	local entity = options.entity or (sound.source == 'charger' and sourceCharger or connectorObject)
	local coords = options.position

	if not coords and sound.source == 'charger' and not options.entity and cableChargerPosition then
		coords = cableChargerPosition
	elseif not coords and entity and DoesEntityExist(entity) then
		coords = GetEntityCoords(entity)
	end

	if not coords then coords = GetEntityCoords(cache.ped) end

	return {
		entityNetId = networkIdForEntity(entity),
		position = { x = coords.x, y = coords.y, z = coords.z },
	}
end

local function playSound(soundName, options)
	local sound = settings.sounds and settings.sounds[soundName]

	if not sound or not soundProviderAvailable() then return end
	options = options or {}

	if settings.soundProvider == 'interact-sound' then
		return TriggerServerEvent('InteractSound_SV:PlayOnSource', sound.name, sound.volume)
	end

	local payload = soundPayload(sound, options)
	local managed = options.managed == true or sound.managed == true

	if managed then
		payload.soundId = soundId(soundName)
		payload.managed = true
		payload.loop = options.loop ~= false and sound.loop ~= false
	elseif options.loop ~= nil then
		payload.loop = options.loop == true
	end

	TriggerServerEvent('ox_fuel:playSound', soundName, payload)
end

local function destroyLocalSound(id)
	if not id or settings.soundProvider ~= 'san_andreas_sound' then return end
	if GetResourceState('san_andreas_sound') ~= 'started' then return end

	pcall(function()
		exports.san_andreas_sound:Destroy(id)
	end)
end

local function stopSound(soundName, force)
	local id = activeSounds[soundName]

	if id then
		activeSounds[soundName] = nil
		destroyLocalSound(id)
	elseif not force then
		return
	end

	if settings.soundProvider ~= 'san_andreas_sound' then return end
	if GetResourceState('san_andreas_sound') ~= 'started' then return end

	TriggerServerEvent('ox_fuel:stopSound', soundName, { soundId = id, force = force == true })
end

local function stopAllSounds()
	for soundName in pairs(settings.sounds or {}) do
		stopSound(soundName, true)
	end

	activeSounds = {}
end

local function playConnectorAnimation(soundName)
	local dictionary = 'anim@am_hold_up@male'
	local clip = 'shoplift_high'

	lib.requestAnimDict(dictionary)
	TaskPlayAnim(cache.ped, dictionary, clip, 2.0, 8.0, -1, 50, 0.0, false, false, false)
	if soundName then playSound(soundName) end
	Wait(soundName == 'chargePutback' and 250 or 300)
	StopAnimTask(cache.ped, dictionary, clip, 1.0)
	RemoveAnimDict(dictionary)
end

local function removeCable()
	if cable and DoesRopeExist(cable) then DeleteRope(cable) end

	cable = nil
	cableChargerPosition = nil
	cableMaxLength = nil
	cablePinnedVertex = nil

	ownsCableTextures = false
end

local function removeConnectorObject()
	if connectorObject and DoesEntityExist(connectorObject) then
		DetachEntity(connectorObject, true, true)
		SetEntityAsMissionEntity(connectorObject, true, true)
		DeleteEntity(connectorObject)
	end

	connectorObject = nil
end

local function cleanup()
	stopSound('chargeLoop', true)

	if selectingOptions then
		checkout.cancel(true)
		selectingOptions = false
	end

	meter.hide()
	meter.clearPump()
	chargingActive = false
	activeSessionId = nil
	activeSessionType = nil
	removeCable()
	removeConnectorObject()
	releaseChargerLease()
	attachedVehicle = nil
	sourceCharger = nil
	sourceType = nil
	chargingSelection = nil
end

local function attachConnectorToHand()
	if not connectorObject or not DoesEntityExist(connectorObject) then return end

	local offset = settings.handOffset or {}
	local rotation = settings.handRotation or {}
	attachedVehicle = nil

	DetachEntity(connectorObject, true, true)
	AttachEntityToEntity(
		connectorObject,
		cache.ped,
		GetPedBoneIndex(cache.ped, 18905),
		offset.x or 0.24, offset.y or 0.10, offset.z or -0.052,
		rotation.x or -45.0, rotation.y or 120.0, rotation.z or 75.0,
		false, true, false, true, 0, true
	)
end

local function getConnectorMountRotation(attachment)
	local baseRotation = attachment.rotation or {}

	if not attachment.profile then
		local automatic = settings.automaticVehicleAttachRotation or {}
		local sideRotation = attachment.side == 'right' and settings.mirrorRightSide ~= false
			and (tonumber(settings.rightSideRotationZ) or 180.0)
			or 0.0

		baseRotation = {
			x = tonumber(automatic.x) or -45.0,
			y = tonumber(automatic.y) or 0.0,
			z = (tonumber(automatic.z) or -90.0) + sideRotation,
		}
	end

	local correction = settings.vehicleAttachRotation or {}

	return {
		x = (baseRotation.x or -45.0) + (correction.x or 0.0),
		y = (baseRotation.y or 0.0) + (correction.y or 0.0),
		z = (baseRotation.z or -90.0) + (correction.z or 0.0),
	}
end

local function getConnectorMountOffset(attachment)
	local correction = settings.vehicleAttachOffset or {}
	local x = tonumber(correction.x) or 0.0
	local y = tonumber(correction.y) or 0.0
	local z = tonumber(correction.z) or 0.0

	if not attachment.profile then
		local automatic = settings.automaticVehicleAttachOffset or {}
		local automaticX = tonumber(automatic.x) or 0.0

		if attachment.side == 'right' and settings.mirrorRightSide ~= false then
			automaticX = -automaticX
		end

		x = x + automaticX
		y = y + (tonumber(automatic.y) or 0.0)
		z = z + (tonumber(automatic.z) or 0.0)
	end

	return { x = x, y = y, z = z }
end

local function attachConnectorToVehicle(vehicle)
	if settings.attachToChargePort == false or not connectorObject or not DoesEntityExist(connectorObject) then return false end
	if not vehicle or not DoesEntityExist(vehicle) then return false end

	local attachment = utils.getVehiclePetrolCapAttachment(vehicle)

	if not attachment or attachment.canAttach == false then return false end

	local baseOffset = attachment.offset or {}
	local offset = getConnectorMountOffset(attachment)
	local rotation = getConnectorMountRotation(attachment)

	DetachEntity(connectorObject, true, true)
	AttachEntityToEntity(
		connectorObject,
		vehicle,
		attachment.boneIndex or 0,
		(baseOffset.x or 0.0) + (offset.x or 0.0),
		(baseOffset.y or 0.0) + (offset.y or 0.0),
		(baseOffset.z or 0.0) + (offset.z or 0.0),
		rotation.x, rotation.y, rotation.z,
		false,
		attachment.useSoftPinning ~= false,
		attachment.collision == true,
		attachment.isPed == true,
		attachment.rotationOrder or 0,
		attachment.syncRot ~= false
	)

	attachedVehicle = vehicle

	return true
end

local function getChargerCablePosition()
	local offset = sourceType == 'portable'
		and (portableSettings.cableOffset or {})
		or (settings.chargerCableOffset or {})

	return GetOffsetFromEntityInWorldCoords(
		sourceCharger,
		offset.x or 0.0,
		offset.y or 0.0,
		offset.z or (sourceType == 'portable' and 0.43 or 1.76)
	)
end

local function getConnectorCablePosition()
	local offset = settings.connectorCableOffset or {}

	return GetOffsetFromEntityInWorldCoords(connectorObject, offset.x or -0.005, offset.y or 0.185, offset.z or -0.05)
end

local function getMaximumCableLength()
	if sourceType == 'portable' then
		return math.max(tonumber(portableSettings.cableMaxLength) or 5.0, 0.5)
	end

	return (sourceCharger and chargers.getCableLength(sourceCharger)) or settings.cableMaxLength or 7.5
end

local function getCableLength(connectorPosition)
	local distance = #(cableChargerPosition - connectorPosition)
	local minimum = sourceType == 'portable'
		and (tonumber(portableSettings.cableLength) or 2.0)
		or (tonumber(settings.cableLength) or 3.0)
	local slack = sourceType == 'portable'
		and (tonumber(portableSettings.cableSlack) or 0.30)
		or (tonumber(settings.cableSlack) or 0.45)

	return math.min(cableMaxLength, math.max(minimum, distance + slack))
end

local function createCable()
	if settings.cable == false then return end

	local texturesWereLoaded = RopeAreTexturesLoaded()

	if not texturesWereLoaded then RopeLoadTextures() end

	local timeout = GetGameTimer() + 5000

	while not RopeAreTexturesLoaded() and GetGameTimer() < timeout do Wait(0) end

	if not RopeAreTexturesLoaded() then
		return print('^3[ox_fuel] Unable to load rope textures; continuing without an EV charging cable.^0')
	end

	ownsCableTextures = not texturesWereLoaded
	cableChargerPosition = getChargerCablePosition()
	local connectorPosition = getConnectorCablePosition()
	cableMaxLength = getMaximumCableLength()
	local initialLength = sourceType == 'portable'
		and (tonumber(portableSettings.cableLength) or 2.0)
		or (tonumber(settings.cableLength) or 3.0)
	local createLength = math.min(initialLength, cableMaxLength)
	local attachLength = getCableLength(connectorPosition)

	cable = AddRope(
		cableChargerPosition.x, cableChargerPosition.y, cableChargerPosition.z,
		0.0, 0.0, 0.0,
		createLength, settings.ropeType or 1, cableMaxLength, 0.0, 1.0,
		false, false, false, 1.0, true, 0
	)

	if not cable or cable == 0 or not DoesRopeExist(cable) then
		removeCable()
		return print('^3[ox_fuel] Unable to create the EV charging cable; continuing with the connector only.^0')
	end

	ActivatePhysics(cable)
	Wait(100)
	connectorPosition = getConnectorCablePosition()
	attachLength = getCableLength(connectorPosition)

	if sourceType == 'portable' then
		local vertexCount = GetRopeVertexCount(cable)

		if vertexCount and vertexCount > 1 then
			cablePinnedVertex = vertexCount - 1
			PinRopeVertex(cable, 0, cableChargerPosition.x, cableChargerPosition.y, cableChargerPosition.z)
			PinRopeVertex(cable, cablePinnedVertex, connectorPosition.x, connectorPosition.y, connectorPosition.z)
		end
	end

	if not cablePinnedVertex then
		AttachEntitiesToRope(
			cable,
			sourceCharger,
			connectorObject,
			cableChargerPosition.x, cableChargerPosition.y, cableChargerPosition.z,
			connectorPosition.x, connectorPosition.y, connectorPosition.z,
			attachLength,
			false, false, nil, nil
		)
	end
	RopeForceLength(cable, attachLength)

	CreateThread(function()
		local heldObject = connectorObject

		while cable and connectorObject == heldObject and DoesEntityExist(heldObject) and DoesRopeExist(cable) do
			local currentConnectorPosition = getConnectorCablePosition()

			if cablePinnedVertex then
				PinRopeVertex(cable, 0, cableChargerPosition.x, cableChargerPosition.y, cableChargerPosition.z)
				PinRopeVertex(
					cable,
					cablePinnedVertex,
					currentConnectorPosition.x,
					currentConnectorPosition.y,
					currentConnectorPosition.z
				)
			end

			RopeForceLength(cable, getCableLength(currentConnectorPosition))
			Wait(cablePinnedVertex and 0 or 250)
		end
	end)
end

local function chargingPayload(initialFuel, fuelAmount, addedKwh, price, pricePerKwh, selection, label, meterState, remainingSeconds, packRemainingKwh)
	local payload = {
		mode = 'charging',
		label = label or locale('charge_meter_charging'),
		state = meterState or 'fueling',
		tankPercent = math.clamp(fuelAmount, 0, 100),
		addedVolume = math.max(tonumber(addedKwh) or 0, 0),
		cost = math.max(tonumber(price) or 0, 0),
		unit = 'kilowatt-hours',
		unitLabel = locale('charge_meter_kwh'),
		unitPrice = math.max(tonumber(pricePerKwh) or 0, 0),
		powerKw = math.max(tonumber(selection and selection.displayPowerKw) or 0, 0),
		remainingSeconds = tonumber(remainingSeconds),
		levelLabel = locale('charge_meter_battery'),
		saleLabel = locale('charge_meter_sale'),
		energyLabel = locale('charge_meter_energy'),
		rateLabel = locale('charge_meter_rate'),
		powerLabel = locale('charge_meter_power'),
		timeLabel = locale('charge_meter_time'),
		costLabel = locale('charge_meter_cost'),
		gradeLabel = selection and selection.modeLabel or nil,
		gradeShortLabel = selection and selection.modeShortLabel or nil,
		paymentLabel = selection and selection.paymentLabel or nil,
		paymentShortLabel = selection and selection.paymentShortLabel or nil,
		initialFuel = initialFuel,
	}

	if sourceType == 'portable' and portablePack then
		local interface = portableSettings.interface or {}
		local capacity = math.max(tonumber(portablePack.capacityKwh) or 0, 0.1)
		local remaining = math.clamp(
			tonumber(packRemainingKwh) or tonumber(portablePack.chargeKwh) or 0,
			0,
			capacity
		)

		payload.sourceType = 'portable'
		payload.brand = locale('portable_terminal_brand')
		payload.packLabel = locale('portable_pack_remaining')
		payload.packRemainingKwh = remaining
		payload.packCapacityKwh = capacity
		payload.packPercent = (remaining / capacity) * 100
		payload.portableLowLabel = locale('portable_low_battery')
		payload.portableCriticalLabel = locale('portable_critical_battery')
		payload.warningBeeps = interface.warningBeeps ~= false
		payload.lowBatteryPercent = math.clamp(tonumber(interface.lowBatteryPercent) or 20.0, 0, 100)
		payload.criticalBatteryPercent = math.clamp(tonumber(interface.criticalBatteryPercent) or 10.0, 0, 100)
		payload.lowBatteryBeepIntervalMs = math.max(tonumber(interface.lowBatteryBeepIntervalMs) or 7500, 1000)
		payload.criticalBatteryBeepIntervalMs = math.max(tonumber(interface.criticalBatteryBeepIntervalMs) or 3500, 750)
		payload.warningBeepVolume = math.clamp(tonumber(interface.warningBeepVolume) or 0.08, 0, 0.35)
	end

	return meter.applyPumpDisplay(payload)
end

local function stopChargingFlow(playStop)
	local wasCharging = chargingActive
	chargingActive = false
	stopSound('chargeLoop', true)

	if playStop and wasCharging then playSound('chargeStop') end
end

local function abortConnector(message, playStop)
	chargingRun = chargingRun + 1

	if activeSessionId then
		TriggerServerEvent(
			activeSessionType == 'portable' and 'ox_fuel:cancelPortableCharging' or 'ox_fuel:cancelCharging',
			activeSessionId
		)
	end

	activeSessionId = nil
	activeSessionType = nil
	state.isFueling = false
	stopChargingFlow(playStop ~= false)
	ClearPedTasks(cache.ped)
	cleanup()

	if message then lib.notify({ type = 'error', description = message }) end
end

function charging.isHolding()
	return connectorObject ~= nil and DoesEntityExist(connectorObject)
end

function charging.isAttachedToVehicle(vehicle)
	if not charging.isHolding() or not attachedVehicle or not DoesEntityExist(attachedVehicle) then
		attachedVehicle = nil
		return false
	end

	return not vehicle or attachedVehicle == vehicle
end

function charging.isInHand()
	return charging.isHolding() and not charging.isAttachedToVehicle()
end

function charging.isCharging()
	return chargingActive
end

function charging.isElectricVehicle(vehicle)
	return vehicle and DoesEntityExist(vehicle) and electricProfiles.isElectricModel(GetEntityModel(vehicle))
end

function charging.isChargerAvailable(charger)
	if chargers.isDestroyed(charger) then return false end
	if occupancySettings.enabled == false then return true end

	local key = getChargerIdentity(charger)
	local owner = key and occupiedChargers[key]

	return not owner or owner == GetPlayerServerId(PlayerId())
end

function charging.isSourceCharger(entity)
	return charging.isHolding() and sourceCharger == entity
end

function charging.isInRange()
	if not charging.isHolding() or not sourceCharger or not DoesEntityExist(sourceCharger) then return false end

	local carriedEntity = charging.isAttachedToVehicle() and connectorObject or cache.ped

	return #(GetEntityCoords(carriedEntity) - GetEntityCoords(sourceCharger)) <= getMaximumCableLength()
end

function charging.getSelection()
	return chargingSelection
end

local showConnectorReady

function charging.chooseOptions()
	if sourceType == 'portable' or not charging.isInHand() or chargingActive or state.isFueling or lib.progressActive() then return end

	selectingOptions = true
	local selection = checkout.selectElectric(chargingSelection, locale('charge_options_title'))
	selectingOptions = false

	if selection and charging.isHolding() then
		chargingSelection = selection
		showConnectorReady()
	end
end

local function portableSelection()
	return {
		modeId = 'portable',
		modeLabel = locale('portable_mode'),
		modeShortLabel = locale('portable_mode_short'),
		pricePerKwh = 0,
		displayPowerKw = math.max(tonumber(portableSettings.displayPowerKw) or 7.2, 0),
		paymentId = 'pack',
		paymentLabel = locale('portable_pack'),
		paymentShortLabel = locale('portable_pack_short'),
		availableFunds = 999999999,
	}
end

showConnectorReady = function()
	local payload = meter.chargingReadyPayload(chargingSelection)

	if sourceType == 'portable' and portablePack then
		local interface = portableSettings.interface or {}
		local capacity = math.max(tonumber(portablePack.capacityKwh) or 0, 0.1)
		local charge = math.clamp(tonumber(portablePack.chargeKwh) or 0, 0, capacity)

		payload.sourceType = 'portable'
		payload.brand = locale('portable_terminal_brand')
		payload.packLabel = locale('portable_pack_remaining')
		payload.packRemainingKwh = charge
		payload.packCapacityKwh = capacity
		payload.packPercent = (charge / capacity) * 100
		payload.portableLowLabel = locale('portable_low_battery')
		payload.portableCriticalLabel = locale('portable_critical_battery')
		payload.warningBeeps = interface.warningBeeps ~= false
		payload.lowBatteryPercent = math.clamp(tonumber(interface.lowBatteryPercent) or 20.0, 0, 100)
		payload.criticalBatteryPercent = math.clamp(tonumber(interface.criticalBatteryPercent) or 10.0, 0, 100)
		payload.lowBatteryBeepIntervalMs = math.max(tonumber(interface.lowBatteryBeepIntervalMs) or 7500, 1000)
		payload.criticalBatteryBeepIntervalMs = math.max(tonumber(interface.criticalBatteryBeepIntervalMs) or 3500, 750)
		payload.warningBeepVolume = math.clamp(tonumber(interface.warningBeepVolume) or 0.08, 0, 0.35)
	end

	meter.show(payload)
end

local function restoreConnectorReady(delay)
	local heldObject = connectorObject

	SetTimeout(delay or 2500, function()
		if connectorObject == heldObject and charging.isInHand() and not state.isFueling then
			showConnectorReady()
		end
	end)
end

local function notifyChargingError(message)
	meter.hide()
	lib.notify({
		type = 'error',
		position = 'top-right',
		description = message,
	})
	restoreConnectorReady()
end

local function beginConnectorSource(charger, connectorSourceType)
	sourceType = connectorSourceType
	sourceCharger = charger
	lib.requestModel(settings.connectorModel)
	playConnectorAnimation('chargePickup')

	if cache.vehicle or state.isFueling then
		SetModelAsNoLongerNeeded(settings.connectorModel)
		cleanup()
		return
	end

	local coords = GetEntityCoords(cache.ped)
	local object = CreateObject(settings.connectorModel, coords.x, coords.y, coords.z, true, true, false)
	SetModelAsNoLongerNeeded(settings.connectorModel)

	if object == 0 then
		cleanup()
		return print('^1[ox_fuel] Unable to create the electric charging connector object.^0')
	end

	connectorObject = object
	SetEntityAsMissionEntity(connectorObject, true, true)
	SetEntityInvincible(connectorObject, true)
	ensureNetworked(connectorObject)
	attachConnectorToHand()
	createCable()
	meter.setPump(charger)
	chargingSelection = connectorSourceType == 'portable' and portableSelection() or checkout.getElectricDefault()
	showConnectorReady()

	CreateThread(function()
		local heldObject = connectorObject
		local heartbeatMs = math.max(tonumber(occupancySettings.heartbeatMs) or 5000, 1000)
		local nextHeartbeat = GetGameTimer() + heartbeatMs

		while connectorObject == heldObject do
			if not DoesEntityExist(heldObject)
				or not sourceCharger
				or not DoesEntityExist(sourceCharger)
				or cache.vehicle
				or IsEntityDead(cache.ped)
			then
				abortConnector()
				break
			end

			if not charging.isInRange() then
				abortConnector(locale('charge_cable_too_far'))
				break
			end

			if pumpLease and GetGameTimer() >= nextHeartbeat then
				TriggerServerEvent('ox_fuel:heartbeatPump', pumpLease.key, pumpLease.token)
				nextHeartbeat = GetGameTimer() + heartbeatMs
			end

			Wait(250)
		end
	end)

	if connectorSourceType ~= 'portable' then
		CreateThread(function()
			local heldObject = connectorObject
			selectingOptions = true
			local selection = checkout.selectElectric(chargingSelection, locale('charge_options_title'))
			selectingOptions = false

			if selection and connectorObject == heldObject then
				chargingSelection = selection
				showConnectorReady()
			end
		end)
	end
end

function charging.take(charger)
	if charging.isHolding() or state.isFueling or cache.vehicle or lib.progressActive() then return end
	if not charger or not DoesEntityExist(charger) then return end
	if chargers.isDestroyed(charger) then
		return lib.notify({ type = 'error', description = locale('charger_destroyed') })
	end

	if state.petrolCan then
		return lib.notify({ type = 'error', description = locale('charge_put_can_away') })
	end

	if not acquireChargerLease(charger) then
		return lib.notify({ type = 'error', description = locale('pump_in_use') })
	end

	beginConnectorSource(charger, 'station')
end

function charging.takePortable(charger)
	if not portablePack or portablePack.object ~= charger then return end
	if charging.isHolding() or state.isFueling or cache.vehicle or lib.progressActive() then return end
	if (tonumber(portablePack.chargeKwh) or 0) <= 0.0001 then
		return lib.notify({ type = 'error', description = locale('portable_empty') })
	end

	if state.petrolCan then
		return lib.notify({ type = 'error', description = locale('charge_put_can_away') })
	end

	beginConnectorSource(charger, 'portable')
end

local function createPortableCarryObject()
	local model = portableSettings.carryModel

	if not model then return end

	lib.requestModel(model)

	local coords = GetEntityCoords(cache.ped)
	local object = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
	SetModelAsNoLongerNeeded(model)

	if object == 0 then return end

	local offset = portableSettings.carryOffset or {}
	local rotation = portableSettings.carryRotation or {}

	AttachEntityToEntity(
		object,
		cache.ped,
		GetPedBoneIndex(cache.ped, 28422),
		offset.x or 0.12, offset.y or 0.02, offset.z or -0.02,
		rotation.x or -85.0, rotation.y or 15.0, rotation.z or 15.0,
		false, true, false, true, 0, true
	)

	return object
end

local function deleteCarryObject(object)
	if object and DoesEntityExist(object) then DeleteEntity(object) end
end

local function playPortableGroundAnimation(pickingUp, packEntity)
	local animation = portableSettings.placementAnimation or {}
	local dictionary = tostring(animation.dictionary or 'pickup_object')
	local clip = tostring(animation.clip or 'pickup_low')
	local duration = math.max(math.floor(tonumber(animation.durationMs) or 950), 500)
	local contactDelay = math.floor(duration * 0.42)
	local carryObject = not pickingUp and createPortableCarryObject() or nil

	SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)

	lib.requestAnimDict(dictionary)
	TaskPlayAnim(cache.ped, dictionary, clip, 4.0, 4.0, duration, 48, 0.0, false, false, false)
	Wait(contactDelay)

	if pickingUp then
		if packEntity and DoesEntityExist(packEntity) then SetEntityVisible(packEntity, false, false) end
		carryObject = createPortableCarryObject()
	else
		deleteCarryObject(carryObject)
		carryObject = nil
	end

	Wait(duration - contactDelay)
	StopAnimTask(cache.ped, dictionary, clip, 1.0)
	RemoveAnimDict(dictionary)
	deleteCarryObject(carryObject)
end

local function removePortableTargets(pack)
	if not pack then return end

	if pack.targetZone then
		exports.ox_target:removeZone(pack.targetZone, true)
	elseif pack.targetNetId then
		exports.ox_target:removeEntity(pack.targetNetId, portableTargetNames)
	elseif pack.targetLocalEntity then
		exports.ox_target:removeLocalEntity(pack.targetLocalEntity, portableTargetNames)
	end

	pack.targetZone = nil
	pack.targetNetId = nil
	pack.targetLocalEntity = nil
end

local function clearPortableFailure(pack)
	if not pack or not pack.failureEffect then return end

	chargers.stopPortableFailure(pack.failureEffect)
	pack.failureEffect = nil
	pack.damaged = false
end

local function deletePortableObject(cancelDeployment)
	local pack = portablePack

	if not pack then return end

	removePortableTargets(pack)
	clearPortableFailure(pack)

	if pack.object and DoesEntityExist(pack.object) then
		SetEntityAsMissionEntity(pack.object, true, true)
		DeleteEntity(pack.object)
	end

	if cancelDeployment and pack.token then
		TriggerServerEvent('ox_fuel:cancelPortableDeployment', pack.token)
	end

	portablePack = nil
end

local function registerPortableTargets(object)
	local distance = math.max(tonumber(portableSettings.interactionDistance) or 2.5, 1.0)

	local options = {
		{
			name = portableTargetNames[1],
			distance = distance,
			icon = 'fas fa-plug',
			label = locale('portable_take_connector'),
			onSelect = function()
				charging.takePortable(portablePack and portablePack.object)
			end,
			canInteract = function()
				return portablePack
					and not portablePack.busy
					and (tonumber(portablePack.chargeKwh) or 0) > 0.0001
					and not charging.isHolding()
					and not portableRechargeActive
					and not state.isFueling
					and not cache.vehicle
					and not lib.progressActive()
			end,
		},
		{
			name = portableTargetNames[2],
			distance = distance,
			icon = 'fas fa-hand',
			label = locale('portable_return_connector'),
			onSelect = function()
				charging.returnToCharger(portablePack and portablePack.object)
			end,
			canInteract = function()
				return sourceType == 'portable'
					and portablePack
					and charging.isSourceCharger(portablePack.object)
					and charging.isInHand()
					and not charging.isCharging()
					and not state.isFueling
			end,
		},
		{
			name = portableTargetNames[3],
			distance = distance,
			icon = 'fas fa-hand',
			label = locale('portable_pickup'),
			onSelect = function()
				charging.pickupPortable()
			end,
			canInteract = function()
				return portablePack
					and not portablePack.busy
					and not charging.isHolding()
					and not portableRechargeActive
					and not state.isFueling
					and not lib.progressActive()
			end,
		},
		{
			name = portableTargetNames[4],
			distance = distance,
			icon = 'fas fa-battery-half',
			label = locale('portable_check_charge'),
			onSelect = function()
				charging.inspectPortable()
			end,
			canInteract = function()
				return portablePack and not portablePack.busy
			end,
		},
	}
	local minimum, maximum = GetModelDimensions(GetEntityModel(object))
	local zoneCoords = GetOffsetFromEntityInWorldCoords(
		object,
		(minimum.x + maximum.x) * 0.5,
		(minimum.y + maximum.y) * 0.5,
		(minimum.z + maximum.z) * 0.5
	)

	portablePack.targetZone = exports.ox_target:addSphereZone({
		coords = zoneCoords,
		radius = math.max(tonumber(portableSettings.targetRadius) or 0.85, 0.25),
		drawSprite = false,
		options = options,
	})
end

function charging.deployPortablePack(item)
	if portableSettings.enabled == false or not item or not item.slot then return end
	if portablePack then
		local object = portablePack.object
		local pickupDistance = math.max(tonumber(portableSettings.pickupDistance) or 3.0, 1.0)

		if not object
			or not DoesEntityExist(object)
			or #(GetEntityCoords(cache.ped) - GetEntityCoords(object)) <= pickupDistance
		then
			return charging.pickupPortable()
		end

		return lib.notify({ type = 'error', description = locale('portable_already_deployed') })
	end
	if charging.isHolding() or portableRechargeActive or state.isFueling or cache.vehicle or lib.progressActive() then return end

	playPortableGroundAnimation(false)

	if cache.vehicle or state.isFueling or IsEntityDead(cache.ped) then return end

	local model = portableSettings.groundModel or `prop_torture_01`
	local deployDistance = math.max(tonumber(portableSettings.deployDistance) or 1.05, 0.5)
	local coords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, deployDistance, 0.0)
	lib.requestModel(model)

	local object = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
	SetModelAsNoLongerNeeded(model)

	if object == 0 then
		return lib.notify({ type = 'error', description = locale('portable_deploy_failed') })
	end

	SetEntityAsMissionEntity(object, true, true)
	SetEntityHeading(object, GetEntityHeading(cache.ped) + (tonumber(portableSettings.deployHeadingOffset) or 0.0))
	PlaceObjectOnGroundProperly(object)
	FreezeEntityPosition(object, true)
	SetEntityInvincible(object, true)
	ClearEntityLastDamageEntity(object)
	ensureNetworked(object)

	local objectCoords = GetEntityCoords(object)
	local deployment = lib.callback.await('ox_fuel:deployPortableCharger', false, item.slot, {
		x = objectCoords.x,
		y = objectCoords.y,
		z = objectCoords.z,
	})

	if not deployment then
		DeleteEntity(object)
		return
	end

	portablePack = {
		object = object,
		token = deployment.token,
		serial = deployment.serial,
		chargeKwh = deployment.chargeKwh,
		capacityKwh = deployment.capacityKwh,
	}
	registerPortableTargets(object)
	lib.notify({ type = 'success', description = locale('portable_deployed') })
end

function charging.pickupPortable()
	local pack = portablePack

	if not pack or pack.busy or charging.isHolding() or portableRechargeActive or state.isFueling then return end

	pack.busy = true
	local pickedUp = lib.callback.await('ox_fuel:pickupPortableCharger', false, pack.token)

	if not pickedUp then
		pack.busy = false
		return
	end

	playPortableGroundAnimation(true, pack.object)
	deletePortableObject(false)
	lib.notify({ type = 'success', description = locale('portable_picked_up') })
end

function charging.inspectPortable()
	if not portablePack then return end

	local capacity = math.max(tonumber(portablePack.capacityKwh) or 0, 0.1)
	local charge = math.clamp(tonumber(portablePack.chargeKwh) or 0, 0, capacity)

	lib.notify({
		type = 'inform',
		description = locale('portable_charge_status', charge, capacity, math.floor((charge / capacity) * 100 + 0.5)),
	})
end

function charging.hasPortablePack()
	return portablePack ~= nil and portablePack.object ~= nil and DoesEntityExist(portablePack.object)
end

function charging.canBuyPortable(charger)
	return portableSettings.enabled ~= false
		and portableSettings.purchaseEnabled ~= false
		and charger
		and DoesEntityExist(charger)
		and charging.isChargerAvailable(charger)
		and not charging.isHolding()
		and not portableRechargeActive
		and not portablePurchaseSessionId
		and not state.isFueling
		and not state.petrolCan
		and not cache.vehicle
		and not lib.progressActive()
end

function charging.canRechargePortable(charger)
	if not charging.hasPortablePack() or portablePack.busy or portableRechargeActive then return false end
	if charging.isHolding() or state.isFueling or cache.vehicle or lib.progressActive() then return false end
	if not charging.isChargerAvailable(charger) then return false end

	local capacity = math.max(tonumber(portablePack.capacityKwh) or 0, 0.1)
	local rechargeDistance = math.max(tonumber(portableSettings.rechargeDistance) or 3.0, 1.0)

	return (tonumber(portablePack.chargeKwh) or 0) < capacity - 0.0001
		and #(GetEntityCoords(portablePack.object) - GetEntityCoords(charger)) <= rechargeDistance
end

function charging.returnToCharger(charger)
	if not charging.isSourceCharger(charger) or not charging.isInHand() or chargingActive or state.isFueling or lib.progressActive() then return end

	playConnectorAnimation('chargePutback')
	cleanup()
end

local function startChargingControls(runId, onCancel)
	CreateThread(function()
		while state.isFueling and chargingRun == runId do
			if IsEntityDead(cache.ped) then
				state.isFueling = false
				break
			end

			DisablePlayerFiring(cache.ped, true)
			DisableControlAction(0, 23, true)
			DisableControlAction(0, 24, true)
			DisableControlAction(0, 25, true)
			DisableControlAction(0, 37, true)
			DisableControlAction(0, 75, true)

			DisableControlAction(0, 21, true)
			DisableControlAction(0, 22, true)
			DisableControlAction(0, 30, true)
			DisableControlAction(0, 31, true)
			DisableControlAction(0, 44, true)

			if IsControlJustPressed(0, 73) then
				onCancel()
				state.isFueling = false
			end

			Wait(0)
		end
	end)
end

local function portablePurchasePayload(transaction, progress, label, meterState)
	progress = math.clamp(tonumber(progress) or 0, 0, 1)

	local capacity = math.max(tonumber(transaction and transaction.capacityKwh) or 0, 0)
	local duration = math.max(tonumber(transaction and transaction.duration) or 0, 0)

	return meter.applyPumpDisplay({
		mode = 'charging',
		sourceType = 'portable-purchase',
		brand = locale('portable_purchase_brand'),
		label = label,
		state = meterState or 'fueling',
		tankPercent = progress * 100,
		addedVolume = capacity * progress,
		cost = math.max(tonumber(transaction and transaction.price) or 0, 0) * progress,
		unit = 'kilowatt-hours',
		unitLabel = locale('charge_meter_kwh'),
		unitPrice = 0,
		powerKw = math.max(tonumber(portableSettings.displayPowerKw) or 7.2, 0),
		remainingSeconds = math.max((duration * (1 - progress)) / 1000, 0),
		levelLabel = locale('portable_pack'),
		energyLabel = locale('portable_capacity'),
		powerLabel = locale('portable_output'),
		timeLabel = locale('charge_meter_time'),
		costLabel = locale('charge_meter_cost'),
		gradeLabel = locale('portable_mode'),
		gradeShortLabel = locale('portable_mode_short'),
		paymentLabel = transaction and transaction.paymentLabel or nil,
		paymentShortLabel = transaction and transaction.paymentShortLabel or nil,
	})
end

function charging.buyPortable(charger)
	if not charging.canBuyPortable(charger) then return end

	meter.setPump(charger)
	meter.show(meter.chargingReadyPayload(checkout.getElectricDefault()))

	local selection = checkout.selectPortablePurchase(locale('portable_buy_options'))

	if not selection or not DoesEntityExist(charger) then
		meter.hide()
		meter.clearPump()
		return
	end

	local chargerCoords = GetEntityCoords(charger)

	TaskTurnPedToFaceEntity(cache.ped, charger, 500)
	Wait(500)

	local transaction = lib.callback.await(
		'ox_fuel:preparePortablePurchase',
		false,
		selection.paymentId,
		GetEntityModel(charger),
		{ x = chargerCoords.x, y = chargerCoords.y, z = chargerCoords.z }
	)

	if not transaction then
		meter.hide()
		meter.clearPump()
		return
	end

	state.isFueling = true
	portablePurchaseSessionId = transaction.id

	local startedAt = GetGameTimer()
	local canceledByPlayer = false
	local completed = false
	local liveLabel = locale('portable_purchasing')

	TaskStartScenarioInPlace(cache.ped, 'PROP_HUMAN_ATM', 0, true)
	meter.show(portablePurchasePayload(transaction, 0, liveLabel))
	chargingRun = chargingRun + 1

	local runId = chargingRun

	startChargingControls(runId, function()
		canceledByPlayer = true
	end)

	while state.isFueling and portablePurchaseSessionId == transaction.id do
		local progress = math.clamp((GetGameTimer() - startedAt) / transaction.duration, 0, 1)

		meter.update(portablePurchasePayload(transaction, progress, liveLabel))

		if progress >= 1 then
			completed = true
			state.isFueling = false
			break
		end

		Wait(math.max(math.floor(tonumber(config.refillTick) or 500), 100))
	end

	state.isFueling = false
	ClearPedTasks(cache.ped)

	local result

	if completed and not canceledByPlayer and portablePurchaseSessionId == transaction.id then
		result = lib.callback.await('ox_fuel:finishPortablePurchase', false, transaction.id)
	elseif portablePurchaseSessionId == transaction.id then
		TriggerServerEvent('ox_fuel:cancelPortablePurchase', transaction.id)
	end

	portablePurchaseSessionId = nil

	if result then
		transaction.price = result.price
		transaction.capacityKwh = result.capacityKwh
		transaction.paymentLabel = result.paymentLabel
		transaction.paymentShortLabel = result.paymentShortLabel
		playPortableGroundAnimation(true)
	end

	local finalPayload = portablePurchasePayload(
		transaction,
		result and 1 or 0,
		locale(result and 'portable_purchase_ready' or 'fuel_meter_stopped'),
		result and 'complete' or 'stopped'
	)

	finalPayload.completed = result ~= nil
	meter.finish(finalPayload, { lingerMs = 1200 })
	meter.clearPump()
end

local function portableRechargePayload(session, selection, chargeKwh, addedKwh, price, label, meterState, remainingSeconds)
	local capacity = math.max(tonumber(session and session.packCapacityKwh) or tonumber(portablePack and portablePack.capacityKwh) or 0, 0.1)
	local charge = math.clamp(tonumber(chargeKwh) or 0, 0, capacity)

	return meter.applyPumpDisplay({
		mode = 'charging',
		sourceType = 'portable-recharge',
		brand = locale('portable_recharge_brand'),
		label = label or locale('portable_recharging'),
		state = meterState or 'fueling',
		tankPercent = (charge / capacity) * 100,
		addedVolume = math.max(tonumber(addedKwh) or 0, 0),
		cost = math.max(tonumber(price) or 0, 0),
		unit = 'kilowatt-hours',
		unitLabel = locale('charge_meter_kwh'),
		unitPrice = math.max(tonumber(session and session.pricePerKwh) or 0, 0),
		powerKw = math.max(tonumber(session and session.displayPowerKw) or 0, 0),
		remainingSeconds = tonumber(remainingSeconds),
		levelLabel = locale('portable_pack'),
		energyLabel = locale('charge_meter_energy'),
		powerLabel = locale('charge_meter_power'),
		timeLabel = locale('charge_meter_time'),
		costLabel = locale('charge_meter_cost'),
		gradeLabel = selection and selection.modeLabel or nil,
		gradeShortLabel = selection and selection.modeShortLabel or nil,
		paymentLabel = selection and selection.paymentLabel or nil,
		paymentShortLabel = selection and selection.paymentShortLabel or nil,
	})
end

local function resetPortableRecharge(hideMeter)
	portableRechargeActive = false
	portableRechargeSessionId = nil
	state.isFueling = false
	stopChargingFlow(false)

	if selectingOptions then
		checkout.cancel(hideMeter == true)
		selectingOptions = false
	end

	if hideMeter then meter.hide() end
	meter.clearPump()
	releaseChargerLease()

	if portablePack then portablePack.busy = false end

	sourceCharger = nil
	sourceType = nil
	chargingSelection = nil
end

local function abortPortableRecharge(message)
	chargingRun = chargingRun + 1

	if portableRechargeSessionId then
		TriggerServerEvent('ox_fuel:cancelPortableRecharge', portableRechargeSessionId)
	end

	resetPortableRecharge(true)

	if message then lib.notify({ type = 'error', description = message }) end
end

function charging.damagePortablePack()
	local pack = portablePack

	if not pack or pack.busy or pack.damaged or not pack.object or not DoesEntityExist(pack.object) then return end

	pack.busy = true

	if portableRechargeActive then
		abortPortableRecharge()
	elseif sourceType == 'portable' then
		abortConnector(nil, true)
	end

	pack.busy = true

	local result = lib.callback.await('ox_fuel:damagePortableCharger', false, pack.token)

	if portablePack ~= pack then return end

	pack.busy = false
	if not result then return end

	pack.chargeKwh = result.chargeKwh or 0
	pack.capacityKwh = result.capacityKwh or pack.capacityKwh
	pack.damaged = true
	pack.failureEffect = chargers.startPortableFailure(
		pack.object,
		GetEntityCoords(pack.object),
		(portableSettings.damageEffects or {}).effectOffset
	)
	lib.notify({ type = 'error', description = locale('portable_damaged') })
end

function charging.rechargePortable(charger)
	if not charging.canRechargePortable(charger) then return end
	if not acquireChargerLease(charger) then
		return lib.notify({ type = 'error', description = locale('pump_in_use') })
	end

	portableRechargeActive = true
	portablePack.busy = true
	sourceCharger = charger
	sourceType = 'portable-recharge'
	meter.setPump(charger)
	chargingSelection = checkout.getElectricDefault()
	selectingOptions = true

	local selection = checkout.selectElectric(chargingSelection, locale('portable_recharge_options'))
	selectingOptions = false

	if not selection or not portablePack or not DoesEntityExist(charger) then
		resetPortableRecharge(true)
		return
	end

	chargingSelection = selection
	local chargerCoords = GetEntityCoords(charger)
	local session = lib.callback.await(
		'ox_fuel:startPortableRecharge',
		false,
		portablePack.token,
		GetEntityModel(charger),
		{ x = chargerCoords.x, y = chargerCoords.y, z = chargerCoords.z },
		selection.modeId,
		selection.paymentId
	)

	if not session or not portablePack then
		resetPortableRecharge(true)
		return
	end

	portableRechargeSessionId = session.id
	selection = {
		modeId = session.modeId,
		modeLabel = session.modeLabel,
		modeShortLabel = session.modeShortLabel,
		pricePerKwh = session.pricePerKwh,
		displayPowerKw = session.displayPowerKw,
		paymentId = session.paymentId,
		paymentLabel = session.paymentLabel,
		paymentShortLabel = session.paymentShortLabel,
		availableFunds = session.availableFunds,
	}
	chargingSelection = selection

	local initialCharge = math.max(tonumber(session.packChargeKwh) or 0, 0)
	local capacity = math.max(tonumber(session.packCapacityKwh) or 0, 0.1)
	local chargeKwh = initialCharge
	local energyPerTick = math.max(tonumber(session.energyPerTick) or 0, 0)
	local maxEnergy = math.max(tonumber(session.maxEnergy) or 0, 0)
	local pricePerKwh = math.max(tonumber(session.pricePerKwh) or 0, 0)
	local moneyAmount = math.max(tonumber(session.availableFunds) or 0, 0)
	local tickSeconds = math.max(tonumber(config.refillTick) or 1, 1) / 1000
	local completedTicks = 0
	local transferredEnergy = 0
	local price = 0
	local canceledByPlayer = false
	local heartbeatMs = math.max(tonumber(occupancySettings.heartbeatMs) or 5000, 1000)
	local nextHeartbeat = GetGameTimer() + heartbeatMs

	state.isFueling = true
	chargingActive = true
	playSound('chargeLoop', { managed = true, entity = charger })
	chargingRun = chargingRun + 1

	local runId = chargingRun
	startChargingControls(runId, function()
		canceledByPlayer = true
	end)

	meter.show(portableRechargePayload(
		session,
		selection,
		chargeKwh,
		0,
		0,
		nil,
		nil,
		session.maxTicks * tickSeconds
	))

	while state.isFueling and portableRechargeSessionId == session.id and completedTicks < session.maxTicks do
		if not portablePack
			or not DoesEntityExist(portablePack.object)
			or not DoesEntityExist(charger)
			or #(GetEntityCoords(portablePack.object) - GetEntityCoords(charger)) > (tonumber(portableSettings.rechargeDistance) or 3.0)
		then
			break
		end

		local nextTicks = completedTicks + 1
		local nextEnergy = math.min(nextTicks * energyPerTick, maxEnergy)
		local nextPrice = roundPrice(nextEnergy * pricePerKwh)

		if nextPrice > moneyAmount then break end

		completedTicks = nextTicks
		transferredEnergy = nextEnergy
		price = nextPrice
		chargeKwh = math.min(initialCharge + transferredEnergy, capacity)

		meter.update(portableRechargePayload(
			session,
			selection,
			chargeKwh,
			transferredEnergy,
			price,
			nil,
			nil,
			math.max(session.maxTicks - completedTicks, 0) * tickSeconds
		))

		if transferredEnergy >= maxEnergy - 0.0001 or completedTicks >= session.maxTicks then
			state.isFueling = false
		end

		if pumpLease and GetGameTimer() >= nextHeartbeat then
			TriggerServerEvent('ox_fuel:heartbeatPump', pumpLease.key, pumpLease.token)
			nextHeartbeat = GetGameTimer() + heartbeatMs
		end

		Wait(config.refillTick)
	end

	state.isFueling = false
	stopChargingFlow(true)

	local result

	if portableRechargeSessionId == session.id then
		portableRechargeSessionId = nil
		result = lib.callback.await('ox_fuel:finishPortableRecharge', false, session.id, completedTicks)
	end

	if result and portablePack then
		portablePack.chargeKwh = result.chargeKwh
		portablePack.capacityKwh = result.capacityKwh or portablePack.capacityKwh
		if portablePack.chargeKwh > 0.0001 then clearPortableFailure(portablePack) end
	end

	local finalCharge = result and result.chargeKwh or initialCharge
	local completed = result and not canceledByPlayer and finalCharge >= capacity - 0.0001
	local finalPayload = portableRechargePayload(
		session,
		selection,
		finalCharge,
		result and result.energy or 0,
		result and result.price or 0,
		locale(completed and 'portable_recharge_complete' or 'fuel_meter_stopped'),
		completed and 'complete' or 'stopped',
		0
	)

	finalPayload.completed = completed == true
	meter.finish(finalPayload)
	resetPortableRecharge(false)
end

function charging.start(vehicle)
	if state.isFueling or not charging.isInHand() then return end
	if not charging.isElectricVehicle(vehicle) then
		return notifyChargingError(locale('charge_electric_only'))
	end
	if not charging.isInRange() then
		return notifyChargingError(locale('charge_cable_too_far'))
	end

	local portDistance = (tonumber(settings.chargePortDistance) or 1.8) + 0.75

	if not utils.isNearVehiclePetrolCap(vehicle, portDistance) then
		return notifyChargingError(locale('charge_port_far'))
	end

	local vehState = Entity(vehicle).state
	local fuelAmount = tonumber(vehState.fuel) or GetVehicleFuelLevel(vehicle)

	if fuelAmount >= 99.999 then
		return notifyChargingError(locale('battery_full'))
	end

	local selection = chargingSelection or checkout.getElectricDefault()
	local portableSession = sourceType == 'portable'

	if portableSession and (not portablePack or (tonumber(portablePack.chargeKwh) or 0) <= 0.0001) then
		return notifyChargingError(locale('portable_empty'))
	end

	meter.hide()
	state.isFueling = true
	local portPosition = utils.getVehiclePetrolCapPosition(vehicle)

	if settings.faceChargePort ~= false and portPosition then
		TaskTurnPedToFaceCoord(cache.ped, portPosition.x, portPosition.y, portPosition.z, 500)
	else
		TaskTurnPedToFaceEntity(cache.ped, vehicle, 500)
	end

	Wait(500)
	chargingActive = true
	playSound('chargeLoop', { managed = true })

	local session

	if portableSession then
		session = lib.callback.await(
			'ox_fuel:startPortableCharging',
			false,
			portablePack.token,
			NetworkGetNetworkIdFromEntity(vehicle),
			fuelAmount
		)
	else
		session = lib.callback.await(
			'ox_fuel:startCharging',
			false,
			NetworkGetNetworkIdFromEntity(vehicle),
			fuelAmount,
			selection.modeId,
			selection.paymentId
		)
	end

	if not session or not charging.isHolding() or not sourceCharger then
		if session then
			TriggerServerEvent(
				portableSession and 'ox_fuel:cancelPortableCharging' or 'ox_fuel:cancelCharging',
				session.id
			)
		end
		state.isFueling = false
		stopChargingFlow(true)
		ClearPedTasks(cache.ped)
		restoreConnectorReady()
		return
	end

	activeSessionId = session.id
	activeSessionType = portableSession and 'portable' or 'station'
	local connectorAttached = attachConnectorToVehicle(vehicle)
	selection = {
		modeId = session.modeId,
		modeLabel = session.modeLabel,
		modeShortLabel = session.modeShortLabel,
		pricePerKwh = session.pricePerKwh,
		displayPowerKw = session.displayPowerKw,
		paymentId = session.paymentId,
		paymentLabel = session.paymentLabel,
		paymentShortLabel = session.paymentShortLabel,
		availableFunds = session.availableFunds,
	}
	chargingSelection = selection

	local initialFuel = session.fuel
	fuelAmount = initialFuel
	local batteryCapacity = math.max(tonumber(session.batteryCapacityKwh) or 0, 0)
	local energyPerTick = math.max(tonumber(session.energyPerTick) or 0, 0)
	local tickSeconds = math.max(tonumber(config.refillTick) or 1, 1) / 1000
	local maxEnergy = math.max(tonumber(session.maxEnergy) or 0, 0)
	local pricePerKwh = math.max(tonumber(session.pricePerKwh) or 0, 0)
	local moneyAmount = math.max(tonumber(session.availableFunds) or 0, 0)
	local packStartCharge = portableSession and math.max(tonumber(session.packChargeKwh) or 0, 0) or nil
	local completedTicks = 0
	local transferredEnergy = 0
	local price = 0
	local completedNaturally = false
	local canceledByPlayer = false
	local chaosFault = session.chaosFault
	local faulted = false
	local dictionary

	if not connectorAttached then
		dictionary = 'timetable@gardener@filling_can'
		lib.requestAnimDict(dictionary)
		TaskPlayAnim(cache.ped, dictionary, 'gar_ig_5_filling_can', 2.0, 2.0, -1, 49, 0.0, false, false, false)
	end
	chargingRun = chargingRun + 1
	local runId = chargingRun

	if connectorAttached then
		ClearPedTasks(cache.ped)
	else
		startChargingControls(runId, function()
			canceledByPlayer = true
		end)
	end

	meter.show(chargingPayload(
		initialFuel,
		fuelAmount,
		0,
		0,
		pricePerKwh,
		selection,
		nil,
		nil,
		session.maxTicks * tickSeconds,
		packStartCharge
	))

	while state.isFueling and activeSessionId == session.id and completedTicks < session.maxTicks do
		if not DoesEntityExist(vehicle)
			or not charging.isInRange()
			or (not connectorAttached and not utils.isNearVehiclePetrolCap(vehicle, portDistance + 0.75))
		then
			break
		end

		local nextTicks = completedTicks + 1
		local nextEnergy = math.min(nextTicks * energyPerTick, maxEnergy)
		local nextPrice = roundPrice(nextEnergy * pricePerKwh)

		if nextPrice > moneyAmount then break end

		completedTicks = nextTicks
		transferredEnergy = nextEnergy
		price = nextPrice
		fuelAmount = math.min(initialFuel + ((transferredEnergy / batteryCapacity) * 100), 100.0)

		meter.update(chargingPayload(
			initialFuel,
			fuelAmount,
			transferredEnergy,
			price,
			pricePerKwh,
			selection,
			nil,
			nil,
			math.max(session.maxTicks - completedTicks, 0) * tickSeconds,
			packStartCharge and math.max(packStartCharge - transferredEnergy, 0) or nil
		))

		if chaosFault
			and not faulted
			and completedTicks >= (tonumber(chaosFault.faultTick) or math.huge)
		then
			faulted = true
			state.isFueling = false
			chargers.playTransientFault(
				sourceCharger,
				portableSession and portableSettings.damageEffects and portableSettings.damageEffects.effectOffset or nil
			)
			lib.notify({
				type = 'error',
				description = locale(portableSession and 'chaos_portable_thermal_shutdown' or 'chaos_rapid_charge_fault'),
			})
		end

		if not faulted and (transferredEnergy >= maxEnergy - 0.0001 or completedTicks >= session.maxTicks) then
			completedNaturally = true
			state.isFueling = false
		end

		Wait(config.refillTick)
	end

	state.isFueling = false
	stopChargingFlow(true)

	if dictionary then
		ClearPedTasks(cache.ped)
		RemoveAnimDict(dictionary)
	end

	local result

	if activeSessionId == session.id then
		activeSessionId = nil
		activeSessionType = nil
		result = lib.callback.await(
			portableSession and 'ox_fuel:finishPortableCharging' or 'ox_fuel:finishCharging',
			false,
			session.id,
			completedTicks
		)
	end

	if portableSession and portablePack and result and result.packChargeKwh ~= nil then
		portablePack.chargeKwh = result.packChargeKwh
		portablePack.capacityKwh = result.packCapacityKwh or portablePack.capacityKwh
	end

	local finalFuel = result and result.fuel or initialFuel
	local finalPrice = result and result.price or 0
	local finalEnergy = result and result.energy or 0
	local completed = result and completedNaturally and not canceledByPlayer
	local finalPayload = chargingPayload(
		initialFuel,
		finalFuel,
		finalEnergy,
		finalPrice,
		pricePerKwh,
		selection,
		locale(faulted
			and (portableSession and 'chaos_portable_thermal_short' or 'chaos_rapid_charge_fault_short')
			or (completed and 'charge_meter_complete' or 'fuel_meter_stopped')),
		completed and 'complete' or 'stopped',
		math.max(session.maxTicks - completedTicks, 0) * tickSeconds,
		portableSession and (result and result.packChargeKwh or packStartCharge) or nil
	)

	finalPayload.completed = completed == true
	meter.finish(finalPayload, { hold = charging.isHolding() })
end

function charging.detachFromVehicle(vehicle)
	if not charging.isAttachedToVehicle(vehicle) then return false end

	state.isFueling = false
	stopChargingFlow(true)
	playConnectorAnimation()
	attachConnectorToHand()

	return true
end

function charging.shutdown()
	stopAllSounds()

	if portablePurchaseSessionId then
		TriggerServerEvent('ox_fuel:cancelPortablePurchase', portablePurchaseSessionId)
		portablePurchaseSessionId = nil
	end

	if portableRechargeActive then abortPortableRecharge() end

	abortConnector(nil, false)
	deletePortableObject(true)
end

RegisterNetEvent('ox_fuel:pumpLeaseLost', function(key, token)
	if not pumpLease or pumpLease.key ~= key or pumpLease.token ~= token then return end

	pumpLease = nil
	occupiedChargers[key] = nil

	if portableRechargeActive then
		abortPortableRecharge(locale('pump_lease_lost'))
	else
		abortConnector(locale('pump_lease_lost'))
	end
end)

AddEventHandler('ox_fuel:chargerDestroying', function(charger)
	if sourceCharger ~= charger then return end

	if portableRechargeActive then
		abortPortableRecharge(locale('charger_destroyed'))
	else
		abortConnector(locale('charger_destroyed'), false)
	end
end)

AddEventHandler('ox_fuel:chargerFaultSound', function(charger, position)
	playSound('chargeFault', { entity = charger, position = position })
end)

AddEventHandler('onClientResourceStop', function(resource)
	if resource == 'san_andreas_sound' then
		activeSounds = {}
	end
end)

CreateThread(function()
	local damage = portableSettings.damageEffects or {}

	if portableSettings.enabled == false or damage.enabled == false then return end

	while true do
		local pack = portablePack

		if not pack
			or pack.busy
			or pack.damaged
			or not pack.object
			or not DoesEntityExist(pack.object)
		then
			Wait(400)
		else
			local entity = pack.object
			local coords = GetEntityCoords(entity)
			local record = {
				entity = entity,
				coords = coords,
				damageable = true,
				destroyed = false,
			}
			local hitEntity
			local hitCoords

			if damage.weaponImpacts ~= false then
				hitEntity, hitCoords = propImpacts.getWeaponHit()
			end

			local weaponHit = damage.weaponImpacts ~= false
				and propImpacts.matchesWeaponHit(record, hitEntity, hitCoords, damage.weaponImpactRadius)
			local vehicleHit = damage.vehicleImpacts ~= false and propImpacts.vehicleWillHit(record, damage)
			local nativeDamage = HasEntityBeenDamagedByAnyObject(entity)
				or HasEntityBeenDamagedByAnyPed(entity)
				or HasEntityBeenDamagedByAnyVehicle(entity)

			if weaponHit or vehicleHit or nativeDamage then
				ClearEntityLastDamageEntity(entity)
				CreateThread(function()
					charging.damagePortablePack()
				end)
				Wait(750)
			else
				Wait(0)
			end
		end
	end
end)

return charging
