local config = require 'config'

local chaos = {}
local settings = config.chaosMode or {}
local activeFires = {}

local function requestControl(entity)
	if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
	if NetworkHasControlOfEntity(entity) then return true end

	local timeout = GetGameTimer() + 750

	repeat
		NetworkRequestControlOfEntity(entity)
		Wait(0)
	until NetworkHasControlOfEntity(entity) or GetGameTimer() >= timeout

	return NetworkHasControlOfEntity(entity)
end

local function notify(key, notificationType)
	lib.notify({
		type = notificationType or 'error',
		description = locale(key),
	})
end

local function damageVehicle(vehicle, outcome)
	if not requestControl(vehicle) then return end

	local engineDamage = math.max(tonumber(outcome.engineDamage) or 0, 0)
	local bodyDamage = math.max(tonumber(outcome.bodyDamage) or 0, 0)

	if engineDamage > 0 then
		SetVehicleEngineHealth(vehicle, GetVehicleEngineHealth(vehicle) - engineDamage)
	end

	if bodyDamage > 0 then
		SetVehicleBodyHealth(vehicle, GetVehicleBodyHealth(vehicle) - bodyDamage)
	end
end

local function vehicleEffectCoords(vehicle)
	local engineBone = GetEntityBoneIndexByName(vehicle, 'engine')

	if engineBone and engineBone ~= -1 then return GetWorldPositionOfEntityBone(vehicle, engineBone) end

	return GetEntityCoords(vehicle)
end

local function startTemporaryFire(vehicle, durationMs)
	local coords = vehicleEffectCoords(vehicle)
	local handle = StartScriptFire(coords.x, coords.y, coords.z, 1, true)

	if handle == nil or handle == -1 then return end

	activeFires[handle] = true

	CreateThread(function()
		Wait(math.max(math.floor(tonumber(durationMs) or 6000), 500))

		if activeFires[handle] then
			RemoveScriptFire(handle)
			activeFires[handle] = nil
		end
	end)
end

local function explodeVehicle(vehicle, outcome)
	local coords = vehicleEffectCoords(vehicle)

	AddExplosion(
		coords.x,
		coords.y,
		coords.z,
		math.floor(tonumber(outcome.explosionType) or 6),
		math.max(tonumber(outcome.damageScale) or 0.6, 0),
		true,
		false,
		math.max(tonumber(outcome.cameraShake) or 0.5, 0),
		false
	)
end

local function applyOutcome(vehicle, outcome, driveOff)
	if type(outcome) ~= 'table' or not vehicle or not DoesEntityExist(vehicle) then return end

	if outcome.type == 'stall' then
		requestControl(vehicle)
		SetVehicleEngineOn(vehicle, false, true, true)
		notify('chaos_engine_stalled', 'warning')
	elseif outcome.type == 'fire' then
		damageVehicle(vehicle, outcome)
		SetVehicleEngineOn(vehicle, false, true, true)
		startTemporaryFire(vehicle, outcome.fireDurationMs)
		notify(driveOff and 'chaos_driveoff_fire' or 'chaos_engine_fire')
	elseif outcome.type == 'explosion' then
		explodeVehicle(vehicle, outcome)
		notify(driveOff and 'chaos_driveoff_explosion' or 'chaos_engine_explosion')
	elseif outcome.type == 'vehicle_damage' then
		damageVehicle(vehicle, outcome)
		notify('chaos_driveoff_vehicle_damage', 'warning')
	elseif outcome.type == 'pump_destroyed' then
		notify('chaos_driveoff_pump_destroyed')
	elseif outcome.type == 'hose_break' then
		notify('chaos_driveoff_hose_broke', 'warning')
	end
end

function chaos.isEnabled()
	return settings.enabled == true
end

function chaos.handleFuelSession(vehicle, result)
	if type(result) ~= 'table' then return end

	if result.warning then notify('chaos_engine_running_warning', 'warning') end
	if result.outcome then applyOutcome(vehicle, result.outcome, false) end

	return result.outcome and result.outcome.type or nil
end

function chaos.handleDriveOff(vehicle, outcome)
	applyOutcome(vehicle, outcome, true)
end

function chaos.cleanup()
	for handle in pairs(activeFires) do RemoveScriptFire(handle) end

	activeFires = {}
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource == GetCurrentResourceName() then chaos.cleanup() end
end)

return chaos
