local config = require 'config'
local propImpacts = require 'client.prop_impacts'

local customPumps = {}
local locations = config.customGasPumpLocations or {}
local propSettings = config.customGasPumpProps or {}
local pumpSettings = {}
local ownedPumps = {}
local configuredPumps = {}
local pumpsByIndex = {}
local stopping = false

local ownershipStateKey = 'oxFuelCustomPumpIndex'

local function getModelHash(prop)
	if type(prop) == 'number' then return prop end
	if type(prop) == 'string' and prop ~= '' then return joaat(prop) end
end

local function isResourcePump(entity, index)
	if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

	return tonumber(Entity(entity).state[ownershipStateKey]) == index
end

local function configureOwnedPump(entity, index, location)
	SetEntityAsMissionEntity(entity, true, true)
	Entity(entity).state:set(ownershipStateKey, index, false)
	SetEntityHeading(entity, location.w or location[4] or 0.0)
	FreezeEntityPosition(entity, true)
	SetEntityInvincible(entity, true)
end

local function deleteOwnedPump(pump)
	local entity = pump and pump.entity

	if not pump or not pump.owned or not entity then return end

	ownedPumps[entity] = nil

	if DoesEntityExist(entity) then
		SetEntityAsMissionEntity(entity, true, true)
		DeleteEntity(entity)
	end
end

local function destroyPump(index, explode)
	local pump = pumpsByIndex[index]

	if not pump or pump.destroyed or not pump.owned then return end

	TriggerEvent('ox_fuel:customPumpDestroying', pump.entity)
	pump.destroyed = true
	pumpSettings[pump.entity] = nil
	deleteOwnedPump(pump)

	if explode then
		AddExplosion(
			pump.coords.x,
			pump.coords.y,
			pump.coords.z,
			math.floor(tonumber(propSettings.explosionType) or 9),
			math.max(tonumber(propSettings.damageScale) or 1.0, 0.0),
			true,
			false,
			math.max(tonumber(propSettings.cameraShake) or 1.0, 0.0),
			false
		)
	end
end

local function spawnPump(entry, index)
	if stopping then return end

	local location = entry.location or entry
	local model = getModelHash(entry.prop)

	if not location or not model or model == 0 or not IsModelInCdimage(model) or not IsModelValid(model) then
		return print(('^3[ox_fuel] Skipping invalid custom gas pump at config index %s.^0'):format(index))
	end

	lib.requestModel(model)

	if stopping then
		SetModelAsNoLongerNeeded(model)
		return
	end

	local entity = GetClosestObjectOfType(
		location.x, location.y, location.z,
		0.75, model, false, false, false
	)
	local entityExists = entity ~= 0 and DoesEntityExist(entity)
	local ownsEntity = entityExists and isResourcePump(entity, index)

	if ownsEntity and (IsEntityDead(entity) or GetEntityHealth(entity) <= 0) then
		SetEntityAsMissionEntity(entity, true, true)
		DeleteEntity(entity)
		entity = 0
		entityExists = false
		ownsEntity = false
	end

	if not entityExists then
		entity = CreateObjectNoOffset(model, location.x, location.y, location.z, false, false, false)
		entityExists = entity ~= 0 and DoesEntityExist(entity)
		ownsEntity = entityExists
	end

	SetModelAsNoLongerNeeded(model)

	if not entityExists then
		return print(('^3[ox_fuel] Unable to create custom gas pump at config index %s.^0'):format(index))
	end

	local damageable = entry.damageable

	if damageable == nil then damageable = propSettings.damageable ~= false end

	if ownsEntity then
		configureOwnedPump(entity, index, location)
		ownedPumps[entity] = true
	end

	local pump = {
		index = index,
		entity = entity,
		owned = ownsEntity,
		damageable = damageable,
		model = model,
		coords = vector3(location.x, location.y, location.z),
		ropeLength = math.max(tonumber(entry.ropeLength) or 0.0, 0.0),
	}

	pumpSettings[entity] = pump
	configuredPumps[#configuredPumps + 1] = pump
	pumpsByIndex[index] = pump
end

function customPumps.getRopeLength(entity)
	local pump = pumpSettings[entity]

	if not pump and entity and DoesEntityExist(entity) then
		local model = GetEntityModel(entity)
		local coords = GetEntityCoords(entity)

		for i = 1, #configuredPumps do
			local configured = configuredPumps[i]

			if not configured.destroyed and configured.model == model and #(coords - configured.coords) <= 1.0 then
				pump = configured
				pumpSettings[entity] = pump
				break
			end
		end
	end

	local ropeLength = pump and not pump.destroyed and pump.ropeLength

	return ropeLength and ropeLength > 0.0 and ropeLength or nil
end

function customPumps.getIndex(entity)
	local pump = pumpSettings[entity]

	if pump and not pump.destroyed then return pump.index end

	if not entity or entity == 0 or not DoesEntityExist(entity) then return end

	local model = GetEntityModel(entity)
	local coords = GetEntityCoords(entity)

	for i = 1, #configuredPumps do
		local configured = configuredPumps[i]

		if not configured.destroyed and configured.model == model and #(coords - configured.coords) <= 1.0 then
			pumpSettings[entity] = configured
			return configured.index
		end
	end
end

function customPumps.cleanup()
	if stopping then return end

	stopping = true

	for i = 1, #configuredPumps do
		deleteOwnedPump(configuredPumps[i])
	end

	pumpSettings = {}
	ownedPumps = {}
	configuredPumps = {}
	pumpsByIndex = {}
end

RegisterNetEvent('ox_fuel:explodeCustomPump', function(index, origin)
	if stopping or origin == GetPlayerServerId(PlayerId()) then return end

	index = tonumber(index)

	if not index or index % 1 ~= 0 then return end

	destroyPump(index, true)
end)

CreateThread(function()
	Wait(250)

	if stopping then return end

	for i = 1, #locations do
		spawnPump(locations[i], i)
	end

	if stopping then return end

	local destroyed = lib.callback.await('ox_fuel:getDestroyedCustomPumps', false)

	if type(destroyed) == 'table' then
		for i = 1, #destroyed do
			destroyPump(tonumber(destroyed[i]), false)
		end
	end

	while not stopping do
		local hitEntity
		local hitCoords

		if propSettings.weaponImpacts ~= false then
			hitEntity, hitCoords = propImpacts.getWeaponHit()
		end

		if hitEntity or hitCoords or (propSettings.vehicleImpacts ~= false and cache.vehicle) then
			for i = 1, #configuredPumps do
				local pump = configuredPumps[i]
				local weaponHit = propSettings.weaponImpacts ~= false
					and propImpacts.matchesWeaponHit(pump, hitEntity, hitCoords, propSettings.weaponImpactRadius)
				local vehicleHit = propSettings.vehicleImpacts ~= false and propImpacts.vehicleWillHit(pump, propSettings)

				if pump.owned and (weaponHit or vehicleHit) then
					destroyPump(pump.index, true)

					if propSettings.synchronizeExplosions ~= false then
						TriggerServerEvent('ox_fuel:customPumpDestroyed', pump.index)
					end

					break
				end
			end
		end

		Wait(0)
	end
end)

return customPumps
