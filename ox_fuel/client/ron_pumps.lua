local config = require 'config'
local hardware = require 'client.charger_hardware'
local display = require 'client.station_display'
local impacts = require 'client.prop_impacts'
local settings = config.ronPump or {}
local damage = config.customGasPumpProps or {}
local pumps = {}
local records, destroyed = {}, {}
local stopping = false

local function key(position)
	local precision = math.max(tonumber((config.pumpOccupancy or {}).coordinatePrecision) or 10, 1)
	local function quantize(value)
		value = value * precision
		return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
	end
	return ('%s:%s:%s:%s'):format(settings.model, quantize(position.x), quantize(position.y), quantize(position.z))
end

local function deleteReplacement(record)
	local entity = record.entity
	record.entity = nil
	if entity then
		-- Abort any held rope before its source is deleted; never delete the map prop.
		TriggerEvent('ox_fuel:customPumpDestroying', entity)
		display.unregister(entity)
		hardware.unregister(entity)
		if DoesEntityExist(entity) then SetEntityAsMissionEntity(entity, true, true) DeleteEntity(entity) end
	end
end

local function unhide(record)
	if not record.hidden then return end
	local p = record.original
	RemoveModelHide(p.x, p.y, p.z, tonumber(settings.hideRadius) or 0.10, settings.originalModel, false)
	record.hidden = nil
end

local function destroy(record, explode)
	if not record or record.destroyed then return end
	record.destroyed = true
	deleteReplacement(record)
	if explode then
		local p = record.coords
		AddExplosion(p.x, p.y, p.z, math.floor(tonumber(damage.explosionType) or 9),
			math.max(tonumber(damage.damageScale) or 1, 0), true, false,
			math.max(tonumber(damage.cameraShake) or 1, 0), false)
	end
end

local function replace(entity)
	if stopping or not DoesEntityExist(entity) then return end
	if Entity(entity).state.oxFuelCustomPumpIndex then return end
	if type(IsEntityAMissionEntity) == 'function' and IsEntityAMissionEntity(entity) then return end
	local original = GetEntityCoords(entity)
	local min = GetModelDimensions(settings.originalModel)
	local floor = GetOffsetFromEntityInWorldCoords(entity, 0, 0, min.z)
	local coords = vector3(floor.x, floor.y, floor.z + (tonumber(settings.zOffset) or 0))
	local identity = key(coords)
	if records[identity] then return end
	local record = { coords = coords, original = original, heading = GetEntityHeading(entity), loading = true, damageable = settings.damageable ~= false }
	records[identity] = record
	local ok = pcall(lib.requestModel, settings.model, 5000)
	if stopping or records[identity] ~= record or not ok or not DoesEntityExist(entity) then
		SetModelAsNoLongerNeeded(settings.model)
		if records[identity] == record then records[identity] = nil end
		return
	end
	local object = CreateObjectNoOffset(settings.model, coords.x, coords.y, coords.z, false, false, false)
	SetModelAsNoLongerNeeded(settings.model)
	if not object or object == 0 then records[identity] = nil return end
	SetEntityAsMissionEntity(object, true, true)
	SetEntityHeading(object, (record.heading + (tonumber(settings.headingOffset) or 0)) % 360)
	FreezeEntityPosition(object, true)
	SetEntityInvincible(object, true)
	if type(SetEntityLodDist) == 'function' then
		SetEntityLodDist(object, math.min(math.max(math.floor(tonumber(settings.modelLodDistance) or 180), 1), 250))
	end
	Entity(object).state:set('oxFuelRonReplacement', true, false)
	record.entity, record.loading = object, false
	CreateModelHideExcludingScriptObjects(original.x, original.y, original.z, tonumber(settings.hideRadius) or 0.10, settings.originalModel, true)
	record.hidden = true
	if destroyed[identity] then destroy(record, false)
	else hardware.register(object, 'pump') display.register(object) end
	return true
end

function pumps.cleanup()
	if stopping then return end
	stopping = true
	for identity, record in pairs(records) do
		deleteReplacement(record)
		unhide(record)
		records[identity] = nil
	end
end

RegisterNetEvent('ox_fuel:ronPumpDestroyed', function(identity, payload, origin)
	if stopping or type(identity) ~= 'string' or type(payload) ~= 'table' then return end
	local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
	if not x or not y or not z or x ~= x or y ~= y or z ~= z then return end
	local position = vector3(x, y, z)
	if key(position) ~= identity then return end
	destroyed[identity] = true
	local record = records[identity]
	if record then destroy(record, origin ~= GetPlayerServerId(PlayerId())) end
end)

if settings.enabled == true then
	CreateThread(function()
		Wait(600)
		local snapshot = lib.callback.await('ox_fuel:getDestroyedRonPumps', false)
		if stopping then return end
		for identity in pairs(type(snapshot) == 'table' and snapshot or {}) do destroyed[identity] = true end
		while not stopping do
			local position = GetEntityCoords(cache.ped)
			local count = 0
			for identity, record in pairs(records) do
				if #(record.coords - position) > (tonumber(settings.despawnDistance) or 80) and not record.loading
					and not hardware.isBusy(record.entity) then
					deleteReplacement(record) unhide(record) records[identity] = nil
				else count = count + 1 end
			end
			for _, entity in ipairs(GetGamePool('CObject')) do
				if DoesEntityExist(entity) then
					local model = GetEntityModel(entity)
					if model == settings.model and not Entity(entity).state.oxFuelRonReplacement then
						hardware.register(entity, 'pump') display.register(entity)
					elseif model == settings.originalModel and count < (tonumber(settings.maxNearby) or 12)
						and #(GetEntityCoords(entity) - position) <= (tonumber(settings.spawnDistance) or 55) then
						if replace(entity) then count = count + 1 end
					end
				end
			end
			Wait(1000)
		end
	end)
	CreateThread(function()
		while not stopping do
			local hitEntity, hitCoords = impacts.getWeaponHit()
			for identity, record in pairs(records) do
				if record.entity and not record.destroyed and record.damageable
					and #(record.coords - GetEntityCoords(cache.ped)) <= (tonumber(settings.reportDistance) or 50) then
					local shot = damage.weaponImpacts ~= false and impacts.matchesWeaponHit(record, hitEntity, hitCoords, damage.weaponImpactRadius)
					local ram = damage.vehicleImpacts ~= false and impacts.vehicleWillHit(record, damage)
					if shot or ram then
						destroyed[identity] = true
						destroy(record, true)
						TriggerServerEvent('ox_fuel:ronPumpDestroyed', { x = record.coords.x, y = record.coords.y, z = record.coords.z })
						break
					end
				end
			end
			Wait(next(records) and 0 or 500)
		end
	end)
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource == GetCurrentResourceName() then pumps.cleanup() end
end)

return pumps
