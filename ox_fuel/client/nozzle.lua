local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local meter = require 'client.meter'
local checkout = require 'client.checkout'
local customPumps = require 'client.custom_pumps'
local chaos = require 'client.chaos'

local settings = config.nozzle
local nozzle = {}

local nozzleObject
local sourcePump
local attachedVehicle
local hose
local hosePumpPosition
local hoseMaxLength
local ownsHoseTextures = false
local fueling = false
local soundCounter = 0
local activeSounds = {}
local occupancySettings = config.pumpOccupancy or {}
local occupiedPumps = {}
local pumpLease
local pumpSelection
local selectingOptions = false

local function clamp(value, min, max)
	if min > max then
		return (min + max) * 0.5
	end

	return math.min(math.max(value, min), max)
end

local function quantizeCoordinate(value)
	local precision = math.max(math.floor(tonumber(occupancySettings.coordinatePrecision) or 10), 1)
	local scaled = value * precision

	return scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)
end

local function getPumpIdentity(pump)
	if not pump or not DoesEntityExist(pump) then return end

	local model = GetEntityModel(pump)
	local coords = GetEntityCoords(pump)
	local key = ('%s:%s:%s:%s'):format(
		model,
		quantizeCoordinate(coords.x),
		quantizeCoordinate(coords.y),
		quantizeCoordinate(coords.z)
	)

	return key, model, { x = coords.x, y = coords.y, z = coords.z }
end

local function acquirePumpLease(pump)
	if occupancySettings.enabled == false then return true end

	local key, model, position = getPumpIdentity(pump)

	if not key then return false end

	local lease = lib.callback.await('ox_fuel:acquirePump', false, model, position)

	if not lease then return false end
	if lease.disabled then return true end

	pumpLease = lease
	occupiedPumps[lease.key] = lease.owner or GetPlayerServerId(PlayerId())

	return true
end

local function releasePumpLease()
	local lease = pumpLease
	pumpLease = nil

	if not lease then return end

	occupiedPumps[lease.key] = nil
	TriggerServerEvent('ox_fuel:releasePump', lease.key, lease.token)
end

RegisterNetEvent('ox_fuel:pumpOccupancyChanged', function(key, owner)
	if type(key) ~= 'string' then return end

	occupiedPumps[key] = owner or nil
end)

CreateThread(function()
	if occupancySettings.enabled == false then return end

	Wait(500)

	local snapshot = lib.callback.await('ox_fuel:getPumpOccupancy', false)

	if type(snapshot) == 'table' then
		occupiedPumps = snapshot
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

local function soundPayload(sound)
	local entity

	if sound.source == 'pump' then
		entity = sourcePump
	elseif sound.source == 'nozzle' then
		entity = nozzleObject
	end

	local coords = entity and DoesEntityExist(entity) and GetEntityCoords(entity) or nil

	if sound.source == 'pump' and hosePumpPosition then
		coords = hosePumpPosition
	end

	if not coords then
		coords = GetEntityCoords(cache.ped)
	end

	return {
		entityNetId = networkIdForEntity(entity),
		position = { x = coords.x, y = coords.y, z = coords.z }
	}
end

local function playSound(soundName, options)
	local sound = settings.sounds[soundName]

	if not sound or not soundProviderAvailable() then return end
	options = options or {}

	if settings.soundProvider == 'interact-sound' then
		return TriggerServerEvent('InteractSound_SV:PlayOnSource', sound.name, sound.volume)
	end

	local payload = soundPayload(sound)
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
	for soundName in pairs(settings.sounds) do
		stopSound(soundName, true)
	end

	activeSounds = {}

	if settings.soundProvider ~= 'san_andreas_sound' then return end
	if GetResourceState('san_andreas_sound') ~= 'started' then return end

	TriggerServerEvent('ox_fuel:stopSound')
end

local function playPumpAnimation(soundName)
	local dictionary = 'anim@am_hold_up@male'

	lib.requestAnimDict(dictionary)
	TaskPlayAnim(cache.ped, dictionary, 'shoplift_high', 2.0, 8.0, -1, 50, 0.0, false, false, false)
	if soundName then playSound(soundName) end
	Wait(300)
	StopAnimTask(cache.ped, dictionary, 'shoplift_high', 1.0)
	RemoveAnimDict(dictionary)
end

local function removeHose()
	if hose and DoesRopeExist(hose) then
		DeleteRope(hose)
	end

	hose = nil
	hosePumpPosition = nil
	hoseMaxLength = nil

	ownsHoseTextures = false
end

local function removeNozzleObject()
	local object = nozzleObject
	nozzleObject = nil

	if object and DoesEntityExist(object) then
		DetachEntity(object, true, true)
		SetEntityAsMissionEntity(object, true, true)
		DeleteEntity(object)
	end
end

local function cleanup()
	stopSound('refuel', true)

	if selectingOptions then
		checkout.cancel(true)
		selectingOptions = false
	end

	meter.hide()
	meter.clearPump()
	fueling = false
	removeHose()
	removeNozzleObject()
	releasePumpLease()
	attachedVehicle = nil
	sourcePump = nil
	pumpSelection = nil
end

local function attachNozzleToHand()
	if not nozzleObject or not DoesEntityExist(nozzleObject) then return end

	attachedVehicle = nil

	DetachEntity(nozzleObject, true, true)
	AttachEntityToEntity(
		nozzleObject,
		cache.ped,
		GetPedBoneIndex(cache.ped, 18905),
		0.13, 0.04, 0.01,
		-42.0, -115.0, -63.42,
		false, true, false, true, 0, true
	)
end

local function getPumpHeight()
	local heights = settings.pumpHeights
	local model = GetEntityModel(sourcePump)

	return (heights and heights[model]) or settings.pumpHeight or 1.25
end

local function getPumpOffset()
	local offsets = settings.pumpOffsets
	local model = GetEntityModel(sourcePump)

	return (offsets and offsets[model]) or settings.pumpOffset
end

local function getPumpAnchorPosition()
	local height = getPumpHeight()

	if settings.anchorToPumpSide == false then
		return GetOffsetFromEntityInWorldCoords(sourcePump, 0.0, 0.0, height)
	end

	local minDim, maxDim = GetModelDimensions(GetEntityModel(sourcePump))

	if not minDim or not maxDim then
		return GetOffsetFromEntityInWorldCoords(sourcePump, 0.0, 0.0, height)
	end

	local edgePadding = settings.pumpEdgePadding or 0.10
	local playerCoords = GetEntityCoords(cache.ped)
	local playerOffset = GetOffsetFromEntityGivenWorldCoords(sourcePump, playerCoords.x, playerCoords.y, playerCoords.z)
	local minX, maxX = minDim.x + edgePadding, maxDim.x - edgePadding
	local minY, maxY = minDim.y + edgePadding, maxDim.y - edgePadding
	local x, y = 0.0, 0.0

	if math.abs(playerOffset.x) > math.abs(playerOffset.y) then
		x = playerOffset.x > 0.0 and maxX or minX
		y = clamp(playerOffset.y, minY, maxY)
	else
		x = clamp(playerOffset.x, minX, maxX)
		y = playerOffset.y > 0.0 and maxY or minY
	end

	local anchorScale = settings.pumpAnchorScale or 0.45
	x = x * anchorScale
	y = y * anchorScale

	local offset = getPumpOffset()

	if offset then
		x = x + (offset.x or 0.0)
		y = y + (offset.y or 0.0)
		height = height + (offset.z or 0.0)
	end

	return GetOffsetFromEntityInWorldCoords(sourcePump, x, y, height)
end

local function getNozzleAnchorPosition()
	local offset = settings.nozzleOffset

	if offset then
		return GetOffsetFromEntityInWorldCoords(nozzleObject, offset.x, offset.y, offset.z)
	end

	return GetOffsetFromEntityInWorldCoords(nozzleObject, 0.0, -0.033, -0.195)
end

local function getMaximumHoseLength()
	local customLength = sourcePump and customPumps.getRopeLength(sourcePump)

	if customLength then return customLength end

	return settings.ropeMaxLength or math.max(settings.hoseLength or 5.0, settings.maxDistance or 7.5)
end

local function getMaximumPumpDistance()
	return (sourcePump and customPumps.getRopeLength(sourcePump)) or settings.maxDistance or 7.5
end

local function getHoseLength(nozzlePosition)
	local distance = #(hosePumpPosition - nozzlePosition)
	local slack = settings.hoseSlack or 0.45
	local minLength = settings.ropeLength or 3.0

	return math.min(hoseMaxLength, math.max(minLength, distance + slack))
end

local function startHoseLengthUpdates(heldObject)
	CreateThread(function()
		while hose
			and nozzleObject == heldObject
			and DoesEntityExist(heldObject)
			and DoesRopeExist(hose)
		do
			RopeForceLength(hose, getHoseLength(getNozzleAnchorPosition()))
			Wait(250)
		end
	end)
end

local function drawAnchorMarker(coords, red, green, blue)
	DrawMarker(
		28,
		coords.x, coords.y, coords.z,
		0.0, 0.0, 0.0,
		0.0, 0.0, 0.0,
		0.08, 0.08, 0.08,
		red, green, blue, 180,
		false, false, 2, false, nil, nil, false
	)
end

local function startDebugMarkers(heldObject)
	if not settings.debug then return end

	CreateThread(function()
		while nozzleObject == heldObject and DoesEntityExist(heldObject) do
			if hosePumpPosition then
				drawAnchorMarker(hosePumpPosition, 255, 80, 80)
			end

			drawAnchorMarker(getNozzleAnchorPosition(), 80, 180, 255)

			if attachedVehicle and DoesEntityExist(attachedVehicle) then
				local fuelcapPosition = utils.getVehiclePetrolCapPosition(attachedVehicle)

				if fuelcapPosition then
					drawAnchorMarker(fuelcapPosition, 80, 255, 120)
				end
			end

			Wait(0)
		end
	end)
end

local function attachNozzleToVehicle(vehicle)
	if not settings.attachToFuelCap or not nozzleObject or not DoesEntityExist(nozzleObject) then return false end
	if not vehicle or not DoesEntityExist(vehicle) then return false end

	local mount = utils.getVehicleFuelNozzleMount(vehicle)

	if not mount or mount.canAttach == false then return false end

	DetachEntity(nozzleObject, true, true)
	AttachEntityToEntity(
		nozzleObject,
		vehicle,
		mount.boneIndex or 0,
		mount.offset.x, mount.offset.y, mount.offset.z,
		mount.rotation.x, mount.rotation.y, mount.rotation.z,
		false,
		mount.useSoftPinning ~= false,
		mount.collision == true,
		mount.isPed == true,
		mount.rotationOrder or 0,
		mount.syncRot ~= false
	)

	attachedVehicle = vehicle

	return true
end

local function createHose()
	if not settings.hose then return end

	local texturesWereLoaded = RopeAreTexturesLoaded()

	if not texturesWereLoaded then RopeLoadTextures() end

	local timeout = GetGameTimer() + 5000

	while not RopeAreTexturesLoaded() and GetGameTimer() < timeout do
		Wait(0)
	end

	if not RopeAreTexturesLoaded() then
		print('^3[ox_fuel] Unable to load rope textures; continuing without a fuel hose.^0')
		return
	end

	ownsHoseTextures = not texturesWereLoaded

	hosePumpPosition = getPumpAnchorPosition()
	local nozzlePosition = getNozzleAnchorPosition()
	hoseMaxLength = getMaximumHoseLength()
	local createLength = math.min(settings.ropeLength or 3.0, hoseMaxLength)
	local attachLength = getHoseLength(nozzlePosition)

	hose = AddRope(
		hosePumpPosition.x, hosePumpPosition.y, hosePumpPosition.z,
		0.0, 0.0, 0.0,
		createLength, settings.ropeType, hoseMaxLength, 0.0, 1.0,
		false, false, false, 1.0, true, 0
	)

	if not hose or hose == 0 or not DoesRopeExist(hose) then
		hose = nil

		ownsHoseTextures = false
		print('^3[ox_fuel] Unable to create the fuel hose; continuing with the nozzle only.^0')
		return
	end

	ActivatePhysics(hose)
	Wait(100)

	nozzlePosition = getNozzleAnchorPosition()
	attachLength = getHoseLength(nozzlePosition)

	AttachEntitiesToRope(
		hose,
		sourcePump,
		nozzleObject,
		hosePumpPosition.x, hosePumpPosition.y, hosePumpPosition.z,
		nozzlePosition.x, nozzlePosition.y, nozzlePosition.z,
		attachLength,
		false, false, nil, nil
	)

	RopeForceLength(hose, attachLength)
	startHoseLengthUpdates(nozzleObject)
	startDebugMarkers(nozzleObject)
end

function nozzle.isHolding()
	return nozzleObject ~= nil and DoesEntityExist(nozzleObject)
end

function nozzle.isAttachedToVehicle(vehicle)
	if not nozzle.isHolding() or not attachedVehicle or not DoesEntityExist(attachedVehicle) then
		attachedVehicle = nil
		return false
	end

	return not vehicle or attachedVehicle == vehicle
end

function nozzle.isInHand()
	return nozzle.isHolding() and not nozzle.isAttachedToVehicle()
end

function nozzle.isPumpAvailable(pump)
	if occupancySettings.enabled == false then return true end

	local key = getPumpIdentity(pump)
	local owner = key and occupiedPumps[key]

	return not owner or owner == GetPlayerServerId(PlayerId())
end

function nozzle.isFueling()
	return fueling
end

function nozzle.getSelection()
	return pumpSelection
end

function nozzle.chooseOptions()
	if not nozzle.isInHand() or fueling or state.isFueling or lib.progressActive() then return end

	selectingOptions = true
	local selection = checkout.select(pumpSelection, locale('fuel_options_title'))
	selectingOptions = false

	if selection and nozzle.isHolding() then
		pumpSelection = selection
		meter.show(meter.readyPayload(pumpSelection))
	end
end

function nozzle.isSourcePump(entity)
	return nozzle.isHolding() and sourcePump == entity
end

function nozzle.isInRange()
	if not nozzle.isHolding() or not sourcePump or not DoesEntityExist(sourcePump) then return false end

	local carriedEntity = nozzle.isAttachedToVehicle() and nozzleObject or cache.ped

	return #(GetEntityCoords(carriedEntity) - GetEntityCoords(sourcePump)) <= getMaximumPumpDistance()
end

function nozzle.startFueling(vehicle)
	if not nozzle.isInHand() or not nozzle.isInRange() then return false end

	fueling = true
	attachNozzleToVehicle(vehicle)
	playSound('refuel', { managed = true })

	return true
end

function nozzle.stopFueling(returnToHand)
	local wasFueling = fueling
	fueling = false
	stopSound('refuel', true)

	if wasFueling then playSound('stop') end
	if returnToHand or not nozzle.isAttachedToVehicle() then attachNozzleToHand() end
end

function nozzle.pauseFueling(durationMs)
	if not fueling then return end

	stopSound('refuel', true)
	playSound('stop')
	Wait(math.max(math.floor(tonumber(durationMs) or 1500), 250))

	if fueling and state.isFueling and nozzle.isHolding() then
		playSound('refuel', { managed = true })
	end
end

function nozzle.detachFromVehicle(vehicle)
	if not nozzle.isAttachedToVehicle(vehicle) then return false end

	state.isFueling = false
	nozzle.stopFueling(false)
	playPumpAnimation()
	attachNozzleToHand()

	return true
end

local function abortNozzle(message)
	if fueling then nozzle.stopFueling() end

	if state.isFueling then
		state.isFueling = false

		if lib.progressActive() then
			lib.cancelProgress()
		end
	end

	cleanup()

	if message then
		lib.notify({ type = 'error', description = message })
	end
end

RegisterNetEvent('ox_fuel:pumpLeaseLost', function(key, token)
	if not pumpLease or pumpLease.key ~= key or pumpLease.token ~= token then return end

	pumpLease = nil
	occupiedPumps[key] = nil
	abortNozzle(locale('pump_lease_lost'))
end)

AddEventHandler('ox_fuel:customPumpDestroying', function(pump)
	if sourcePump == pump then abortNozzle(locale('fuel_pump_destroyed')) end
end)

function nozzle.take(pump)
	if nozzle.isHolding() or state.isFueling or cache.vehicle or lib.progressActive() then return end
	if not pump or not DoesEntityExist(pump) then return end

	if state.petrolCan then
		return lib.notify({ type = 'error', description = locale('pump_fuel_with_can') })
	end

	if not acquirePumpLease(pump) then
		return lib.notify({ type = 'error', description = locale('pump_in_use') })
	end

	sourcePump = pump

	lib.requestModel(settings.model)
	playPumpAnimation('pickup')

	if cache.vehicle or state.isFueling then
		SetModelAsNoLongerNeeded(settings.model)
		cleanup()
		return
	end

	local coords = GetEntityCoords(cache.ped)
	local object = CreateObject(settings.model, coords.x, coords.y, coords.z, true, true, false)

	SetModelAsNoLongerNeeded(settings.model)

	if object == 0 then
		cleanup()
		return print('^1[ox_fuel] Unable to create the fuel nozzle object.^0')
	end

	nozzleObject = object
	sourcePump = pump

	SetEntityAsMissionEntity(nozzleObject, true, true)
	SetEntityInvincible(nozzleObject, true)
	ensureNetworked(nozzleObject)
	attachNozzleToHand()

	createHose()
	meter.setPump(pump)
	pumpSelection = checkout.getDefault()
	meter.show(meter.readyPayload(pumpSelection))

	CreateThread(function()
		local heldObject = nozzleObject
		local heartbeatMs = math.max(tonumber(occupancySettings.heartbeatMs) or 5000, 1000)
		local nextHeartbeat = GetGameTimer() + heartbeatMs

		while nozzleObject == heldObject do
			if not DoesEntityExist(heldObject)
				or not sourcePump
				or not DoesEntityExist(sourcePump)
				or cache.vehicle
				or IsEntityDead(cache.ped)
			then
				abortNozzle()
				break
			end

			if not nozzle.isInRange() then
				local vehicle = attachedVehicle and DoesEntityExist(attachedVehicle) and attachedVehicle or nil
				local outcome

				if chaos.isEnabled() and fueling and state.isFueling and vehicle then
					state.isFueling = false
					outcome = lib.callback.await(
						'ox_fuel:chaosDriveOff',
						false,
						NetworkGetNetworkIdFromEntity(vehicle),
						customPumps.getIndex(sourcePump)
					)

					if outcome then chaos.handleDriveOff(vehicle, outcome) end
				end

				if nozzleObject == heldObject then
					local message

					if not outcome then message = locale('nozzle_too_far') end

					abortNozzle(message)
				end
				break
			end

			if pumpLease and GetGameTimer() >= nextHeartbeat then
				TriggerServerEvent('ox_fuel:heartbeatPump', pumpLease.key, pumpLease.token)
				nextHeartbeat = GetGameTimer() + heartbeatMs
			end

			Wait(250)
		end
	end)

	CreateThread(function()
		local heldObject = nozzleObject
		selectingOptions = true
		local selection = checkout.select(pumpSelection, locale('fuel_options_title'))
		selectingOptions = false

		if selection and nozzleObject == heldObject then
			pumpSelection = selection
			meter.show(meter.readyPayload(pumpSelection))
		end
	end)
end

function nozzle.returnToPump(pump)
	if not nozzle.isSourcePump(pump) or not nozzle.isInHand() or fueling or state.isFueling or lib.progressActive() then return end

	playPumpAnimation('putback')
	cleanup()
end

function nozzle.shutdown()
	stopAllSounds()
	cleanup()
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource == 'san_andreas_sound' then
		activeSounds = {}
	end
end)

return nozzle
