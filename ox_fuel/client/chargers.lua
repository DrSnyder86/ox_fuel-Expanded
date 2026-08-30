local config = require 'config'
local utils = require 'client.utils'
local propImpacts = require 'client.prop_impacts'

local settings = config.electric or {}
local damageSettings = settings.damageEffects or {}
local chargers = {}
local spawned = {}
local recordsByEntity = {}
local recordsByIndex = {}
local destroyedEntities = {}
local originalHeadings = {}
local blips = {}
local blipPoints = {}
local failureEffects = {}
local loadedParticleAssets = {}
local failedParticleAssets = {}
local stopping = false
local transientFaultCounter = 0

local ownershipStateKey = 'oxFuelElectricChargerIndex'

local function isDamageable(entry)
	if damageSettings.enabled == false then return false end

	local damageable = entry.damageable

	if damageable == nil then damageable = damageSettings.damageable ~= false end

	return damageable == true
end

local function removeChargerBlip(blip)
	if not blip then return end

	blips[blip] = nil

	if DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function createChargerBlip(coords)
	local blipSettings = settings.blip or {}
	local blip = utils.createBlip(coords, {
		sprite = blipSettings.sprite or 620,
		colour = blipSettings.colour or 3,
		scale = blipSettings.scale or 0.55,
		display = blipSettings.display or 4,
		shortRange = blipSettings.shortRange ~= false,
		name = 'ox_electric_station',
	})

	blips[blip] = true

	return blip
end

local function setupBlips(locations)
	local mode = math.clamp(math.floor(tonumber(settings.showBlips) or 1), 0, 2)

	if mode == 0 then return end

	for i = 1, #locations do
		local entry = locations[i]
		local location = entry.location or entry

		if location then
			if mode == 2 then
				createChargerBlip(location)
			else
				local point = lib.points.new({
					coords = vector3(location.x, location.y, location.z),
					distance = math.max(tonumber(settings.blip and settings.blip.nearbyDistance) or 60.0, 1.0),
					onEnter = function(self)
						if not self.blip then self.blip = createChargerBlip(self.coords) end
					end,
					onExit = function(self)
						removeChargerBlip(self.blip)
						self.blip = nil
					end,
				})

				blipPoints[#blipPoints + 1] = point
			end
		end
	end
end

local function isResourceCharger(entity, index)
	if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

	return tonumber(Entity(entity).state[ownershipStateKey]) == index
end

local function configureOwnedCharger(entity, index, location)
	SetEntityAsMissionEntity(entity, true, true)
	Entity(entity).state:set(ownershipStateKey, index, false)
	SetEntityHeading(entity, ((location.w or location[4] or 0.0) + (tonumber(settings.headingOffset) or 0.0)) % 360.0)
	FreezeEntityPosition(entity, true)
	SetEntityInvincible(entity, true)
end

local function remember(entity, index, ownsEntity, entry, location)
	local record = {
		index = index,
		entity = entity,
		owned = ownsEntity == true,
		damageable = isDamageable(entry),
		coords = vector3(location.x, location.y, location.z),
		cableLength = math.max(tonumber(entry.cableLength) or tonumber(settings.cableMaxLength) or 7.5, 0.1),
	}

	spawned[#spawned + 1] = record
	recordsByEntity[entity] = record
	recordsByIndex[index] = record

	return record
end

local function isEffectNearby(record)
	if not cache.ped or not DoesEntityExist(cache.ped) then return false end

	return #(GetEntityCoords(cache.ped) - record.coords) <= math.max(tonumber(damageSettings.renderDistance) or 125.0, 1.0)
end

local function particleCoords(record, particle)
	local offset = particle and particle.offset or {}
	local correction = record.effectOffset or {}
	local x = (tonumber(offset.x) or 0.0) + (tonumber(correction.x) or 0.0)
	local y = (tonumber(offset.y) or 0.0) + (tonumber(correction.y) or 0.0)
	local z = (tonumber(offset.z) or 0.0) + (tonumber(correction.z) or 0.0)

	if record.entity and DoesEntityExist(record.entity) then
		return GetOffsetFromEntityInWorldCoords(record.entity, x, y, z)
	end

	return vector3(record.coords.x + x, record.coords.y + y, record.coords.z + z)
end

local function requestParticleAsset(asset)
	if type(asset) ~= 'string' or asset == '' or failedParticleAssets[asset] then return false end
	if loadedParticleAssets[asset] or HasNamedPtfxAssetLoaded(asset) then
		loadedParticleAssets[asset] = true
		return true
	end

	RequestNamedPtfxAsset(asset)
	local timeout = GetGameTimer() + 5000

	while not stopping and not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < timeout do Wait(0) end

	if stopping or not HasNamedPtfxAssetLoaded(asset) then
		failedParticleAssets[asset] = true
		return false
	end

	loadedParticleAssets[asset] = true
	return true
end

local function particleColour(particle)
	local colour = particle.colour or (damageSettings.flash and damageSettings.flash.colour) or {}

	return math.clamp((tonumber(colour.r) or 255) / 255, 0.0, 1.0),
		math.clamp((tonumber(colour.g) or 255) / 255, 0.0, 1.0),
		math.clamp((tonumber(colour.b) or 255) / 255, 0.0, 1.0)
end

local function startNonLoopedParticle(particle, coords)
	if stopping or not particle or not particle.name or not requestParticleAsset(particle.asset) then return end

	local red, green, blue = particleColour(particle)
	UseParticleFxAssetNextCall(particle.asset)
	SetParticleFxNonLoopedColour(red, green, blue)
	StartParticleFxNonLoopedAtCoord(
		particle.name,
		coords.x,
		coords.y,
		coords.z,
		0.0,
		0.0,
		0.0,
		math.max(tonumber(particle.scale) or 1.0, 0.01),
		false,
		false,
		false
	)
end

local function startSmoke(record, effect)
	local particle = damageSettings.smoke

	if stopping or not particle or particle.enabled == false or not particle.name then return end
	if effect.smokeHandle or effect.smokePending then return end
	if not isEffectNearby(record) then return end

	effect.smokePending = true

	if not requestParticleAsset(particle.asset) or stopping or record.destroyed ~= true then
		effect.smokePending = false
		return
	end

	local coords = particleCoords(record, particle)
	UseParticleFxAssetNextCall(particle.asset)
	local handle = StartParticleFxLoopedAtCoord(
		particle.name,
		coords.x,
		coords.y,
		coords.z,
		0.0,
		0.0,
		0.0,
		math.max(tonumber(particle.scale) or 0.18, 0.01),
		false,
		false,
		false,
		false
	)

	if handle and handle ~= 0 then
		effect.smokeHandle = handle
	end

	effect.smokePending = false
end

local function sparkBurst(record, count)
	local particle = damageSettings.sparks

	if stopping or not particle or particle.enabled == false or not particle.name then return end
	if not isEffectNearby(record) then return end

	count = math.max(math.floor(tonumber(count) or 1), 1)

	for i = 1, count do
		if stopping then return end

		local coords = particleCoords(record, particle)
		startNonLoopedParticle(particle, vector3(coords.x, coords.y, coords.z + ((i - 1) * 0.025)))

		if i < count then Wait(55) end
	end
end

local function shockNearbyPlayer(record)
	if damageSettings.playerShock ~= true or not cache.ped or not DoesEntityExist(cache.ped) then return end

	local radius = math.max(tonumber(damageSettings.shockRadius) or 2.0, 0.0)

	if #(GetEntityCoords(cache.ped) - record.coords) > radius then return end

	ApplyDamageToPed(cache.ped, math.max(math.floor(tonumber(damageSettings.shockDamage) or 5), 0), false)
	SetPedToRagdoll(
		cache.ped,
		math.max(math.floor(tonumber(damageSettings.shockRagdollMs) or 1000), 0),
		math.max(math.floor(tonumber(damageSettings.shockRagdollMs) or 1000), 0),
		0,
		false,
		false,
		false
	)
end

local function stopSmoke(effect)
	if effect and effect.smokeHandle then
		StopParticleFxLooped(effect.smokeHandle, false)
		effect.smokeHandle = nil
	end
end

local function startFailureEffects(record, showFailure, playFaultSound)
	if damageSettings.enabled == false then return end

	local now = GetGameTimer()
	local flash = damageSettings.flash or {}
	local sparks = damageSettings.sparks or {}
	local smoke = damageSettings.smoke or {}
	local intervalMin = math.max(math.floor(tonumber(sparks.intervalMinMs) or 2500), 250)
	local intervalMax = math.max(math.floor(tonumber(sparks.intervalMaxMs) or 6000), intervalMin)
	local effect = {
		record = record,
		flashUntil = showFailure and flash.enabled ~= false and now + math.max(math.floor(tonumber(flash.durationMs) or 850), 0) or 0,
		flickerUntil = 0,
		nextSpark = sparks.enabled ~= false and sparks.name and now + math.random(intervalMin, intervalMax) or math.huge,
		smokeEndsAt = smoke.enabled ~= false and smoke.name and now + math.max(math.floor(tonumber(smoke.durationMs) or 45000), 1000) or 0,
	}

	failureEffects[record.index] = effect

	if playFaultSound then
		TriggerEvent('ox_fuel:chargerFaultSound', record.entity, {
			x = record.coords.x,
			y = record.coords.y,
			z = record.coords.z,
		})
	end

	if showFailure then
		shockNearbyPlayer(record)
		CreateThread(function()
			sparkBurst(record, math.max(math.floor(tonumber(sparks.burstCount) or 3), 1))
		end)
	end

	CreateThread(function()
		startSmoke(record, effect)
	end)
end

local function destroyCharger(index, showFailure, playFaultSound)
	local record = recordsByIndex[index]

	if not record or record.destroyed then return end

	TriggerEvent('ox_fuel:chargerDestroying', record.entity)
	record.destroyed = true
	destroyedEntities[record.entity] = true

	if record.owned and DoesEntityExist(record.entity) then
		SetEntityInvincible(record.entity, true)
		FreezeEntityPosition(record.entity, true)
	end

	startFailureEffects(record, showFailure == true, playFaultSound == true)
end

function chargers.getCableLength(entity)
	local record = recordsByEntity[entity]

	return record and not record.destroyed and record.cableLength or nil
end

function chargers.isDestroyed(entity)
	if not entity or entity == 0 then return false end
	if destroyedEntities[entity] then return true end

	local record = recordsByEntity[entity]

	return record and record.destroyed == true or false
end

function chargers.playTransientFault(entity, effectOffset)
	if stopping or not entity or entity == 0 or not DoesEntityExist(entity) then return end

	transientFaultCounter = transientFaultCounter + 1
	local position = GetEntityCoords(entity)

	TriggerEvent('ox_fuel:chargerFaultSound', entity, {
		x = position.x,
		y = position.y,
		z = position.z,
	})

	if damageSettings.enabled == false then return end

	local record = {
		index = ('transient:%s:%s'):format(entity, transientFaultCounter),
		entity = entity,
		coords = vector3(position.x, position.y, position.z),
		destroyed = true,
		effectOffset = effectOffset,
	}
	local flash = damageSettings.flash or {}
	local colour = flash.colour or {}
	local durationMs = math.max(math.floor(tonumber(flash.durationMs) or 850), 150)
	local endsAt = GetGameTimer() + durationMs

	CreateThread(function()
		sparkBurst(record, math.max(math.floor(tonumber(damageSettings.sparks and damageSettings.sparks.burstCount) or 3), 1))
	end)

	if flash.enabled == false then return end

	CreateThread(function()
		while not stopping and GetGameTimer() < endsAt do
			if isEffectNearby(record) then
				local now = GetGameTimer()
				local coords = particleCoords(record, damageSettings.sparks or {})
				local pulse = 0.72 + (math.sin(now * 0.045) * 0.28)

				DrawLightWithRange(
					coords.x,
					coords.y,
					coords.z,
					math.floor(tonumber(colour.r) or 23),
					math.floor(tonumber(colour.g) or 192),
					math.floor(tonumber(colour.b) or 235),
					math.max(tonumber(flash.range) or 7.0, 0.0),
					math.max(tonumber(flash.intensity) or 12.0, 0.0) * pulse
				)
			end

			Wait(0)
		end
	end)
end

function chargers.startPortableFailure(entity, coords, effectOffset)
	if damageSettings.enabled == false or not entity or not DoesEntityExist(entity) then return end

	local index = ('portable:%s'):format(entity)
	local existing = failureEffects[index]

	if existing then stopSmoke(existing) end

	local position = coords or GetEntityCoords(entity)
	local record = {
		index = index,
		entity = entity,
		coords = vector3(position.x, position.y, position.z),
		destroyed = true,
		effectOffset = effectOffset,
	}

	startFailureEffects(record, true, true)

	return index
end

function chargers.stopPortableFailure(index)
	local effect = index and failureEffects[index]

	if not effect then return end

	stopSmoke(effect)
	failureEffects[index] = nil
end

RegisterNetEvent('ox_fuel:destroyCharger', function(index, origin)
	if stopping or origin == GetPlayerServerId(PlayerId()) then return end

	index = tonumber(index)

	if not index or index % 1 ~= 0 then return end

	destroyCharger(index, true, false)
end)

CreateThread(function()
	if settings.enabled == false or not settings.chargerModel then return end

	Wait(250)

	if stopping then return end

	local locations = settings.chargerLocations or {}

	if #locations == 0 then return end
	setupBlips(locations)

	lib.requestModel(settings.chargerModel)

	if stopping then
		SetModelAsNoLongerNeeded(settings.chargerModel)
		return
	end

	for i = 1, #locations do
		if stopping then break end

		local entry = locations[i]
		local location = entry.location or entry

		if location then
			local entity = GetClosestObjectOfType(
				location.x,
				location.y,
				location.z,
				0.75,
				settings.chargerModel,
				false,
				false,
				false
			)
			local entityExists = entity ~= 0 and DoesEntityExist(entity)
			local ownsEntity = entityExists and isResourceCharger(entity, i)

			if ownsEntity and (IsEntityDead(entity) or GetEntityHealth(entity) <= 0) then
				SetEntityAsMissionEntity(entity, true, true)
				DeleteEntity(entity)
				entity = 0
				entityExists = false
				ownsEntity = false
			end

			if not entityExists then
				entity = CreateObjectNoOffset(settings.chargerModel, location.x, location.y, location.z, false, false, false)
				entityExists = entity ~= 0 and DoesEntityExist(entity)
				ownsEntity = entityExists
			end

			if entityExists then
				local damageable = isDamageable(entry)

				if ownsEntity then
					configureOwnedCharger(entity, i, location)
				else
					originalHeadings[entity] = GetEntityHeading(entity)
					SetEntityHeading(entity, ((location.w or location[4] or 0.0) + (tonumber(settings.headingOffset) or 0.0)) % 360.0)
				end

				remember(entity, i, ownsEntity, entry, location)
			else
				print(('^3[ox_fuel] Unable to create electric charger at config index %s.^0'):format(i))
			end
		end
	end

	SetModelAsNoLongerNeeded(settings.chargerModel)

	if stopping then return end

	local destroyed = lib.callback.await('ox_fuel:getDestroyedChargers', false)

	if type(destroyed) == 'table' then
		for i = 1, #destroyed do
			destroyCharger(tonumber(destroyed[i]), false, false)
		end
	end

	while not stopping do
		local now = GetGameTimer()
		local hitEntity
		local hitCoords

		if damageSettings.weaponImpacts ~= false then
			hitEntity, hitCoords = propImpacts.getWeaponHit()
		end

		if hitEntity or hitCoords or (damageSettings.vehicleImpacts ~= false and cache.vehicle) then
			for i = 1, #spawned do
				local record = spawned[i]
				local weaponHit = damageSettings.weaponImpacts ~= false
					and propImpacts.matchesWeaponHit(record, hitEntity, hitCoords, damageSettings.weaponImpactRadius)
				local vehicleHit = damageSettings.vehicleImpacts ~= false and propImpacts.vehicleWillHit(record, damageSettings)

				if record.owned and (weaponHit or vehicleHit) then
					destroyCharger(record.index, true, true)

					if damageSettings.synchronize ~= false then
						TriggerServerEvent('ox_fuel:chargerDestroyed', record.index)
					end

					break
				end
			end
		end

		for _, effect in pairs(failureEffects) do
			local flash = damageSettings.flash or {}
			local colour = flash.colour or {}
			local intensity

			if now < effect.flashUntil then
				local pulse = 0.72 + (math.sin(now * 0.045) * 0.28)
				intensity = math.max(tonumber(flash.intensity) or 12.0, 0.0) * pulse
			elseif now < effect.flickerUntil then
				intensity = math.max(tonumber(flash.intensity) or 12.0, 0.0) * 0.45
			end

			if intensity and isEffectNearby(effect.record) then
				local coords = particleCoords(effect.record, damageSettings.sparks or {})

				DrawLightWithRange(
					coords.x,
					coords.y,
					coords.z,
					math.floor(tonumber(colour.r) or 23),
					math.floor(tonumber(colour.g) or 192),
					math.floor(tonumber(colour.b) or 235),
					math.max(tonumber(flash.range) or 7.0, 0.0),
					intensity
				)
			end

			if effect.smokeHandle and effect.smokeEndsAt and now >= effect.smokeEndsAt then
				stopSmoke(effect)
			elseif not effect.smokeHandle and effect.smokeEndsAt > 0 and now < effect.smokeEndsAt and isEffectNearby(effect.record) then
				local effectRecord = effect.record
				local currentEffect = effect

				CreateThread(function()
					startSmoke(effectRecord, currentEffect)
				end)
			end

			if now >= effect.nextSpark then
				local sparks = damageSettings.sparks or {}
				local intervalMin = math.max(math.floor(tonumber(sparks.intervalMinMs) or 2500), 250)
				local intervalMax = math.max(math.floor(tonumber(sparks.intervalMaxMs) or 6000), intervalMin)

				effect.nextSpark = now + math.random(intervalMin, intervalMax)
				effect.flickerUntil = now + 150
				local effectRecord = effect.record

				CreateThread(function()
					sparkBurst(effectRecord, 1)
				end)
			end
		end

		Wait(0)
	end
end)

function chargers.cleanup()
	if stopping then return end

	stopping = true

	for _, effect in pairs(failureEffects) do stopSmoke(effect) end

	for i = 1, #spawned do
		local record = spawned[i]
		local entity = record.entity

		if record.owned and DoesEntityExist(entity) then
			SetEntityAsMissionEntity(entity, true, true)
			DeleteEntity(entity)
		elseif originalHeadings[entity] and DoesEntityExist(entity) then
			SetEntityHeading(entity, originalHeadings[entity])
		end
	end

	for blip in pairs(blips) do removeChargerBlip(blip) end

	for i = 1, #blipPoints do
		local point = blipPoints[i]

		if point.remove then point:remove() end
	end

	spawned = {}
	recordsByEntity = {}
	recordsByIndex = {}
	destroyedEntities = {}
	originalHeadings = {}
	blips = {}
	blipPoints = {}
	failureEffects = {}
	loadedParticleAssets = {}
	failedParticleAssets = {}
end

return chargers
