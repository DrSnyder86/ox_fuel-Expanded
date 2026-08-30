local config = require 'config'
local fuelGrades = require 'fuel_grades'
local vehicleProfiles = require 'vehicle_profiles'
local electricProfiles = require 'electric_profiles'

if not config then return end

local globalConsumptionRate = math.max(tonumber(config.globalFuelConsumptionRate) or 1.0, 0)

SetFuelConsumptionState(true)
SetFuelConsumptionRateMultiplier(globalConsumptionRate)

AddTextEntry('fuelHelpText', locale('fuel_help'))
AddTextEntry('petrolcanHelpText', locale('petrolcan_help'))
AddTextEntry('fuelLeaveVehicleText', locale('leave_vehicle'))
AddTextEntry('ox_fuel_station', locale('fuel_station_blip'))
AddTextEntry('ox_electric_station', locale('electric_station_blip'))

local utils = require 'client.utils'
local state = require 'client.state'
local fuel  = require 'client.fuel'

local customPumps = require 'client.custom_pumps'
local chargers = require 'client.chargers'
require 'client.stations'

local function startDrivingVehicle()
	local vehicle = cache.vehicle
	local model = GetEntityModel(vehicle)
	local electricProfile = electricProfiles.resolve(model)

	if not electricProfile and not DoesVehicleUseFuel(vehicle) then return end

	local profile = electricProfile or vehicleProfiles.resolve(model, GetVehicleClass(vehicle))
	local consumptionRate = globalConsumptionRate * profile.consumptionRate
	local electricConsumption = math.max(tonumber(config.electric and config.electric.consumptionPercentPerSecond) or 0.025, 0)

	local vehState = Entity(vehicle).state

	if not vehState.fuel then
		vehState:set('fuel', GetVehicleFuelLevel(vehicle), true)
		while not vehState.fuel do Wait(0) end
	end

	SetVehicleFuelLevel(vehicle, vehState.fuel)

	local fuelTick = 0

	while cache.seat == -1 do
		if GetIsVehicleEngineRunning(vehicle) then
			if not DoesEntityExist(vehicle) then return end

			local fuelAmount = tonumber(vehState.fuel)
			local newFuel

			if electricProfile then
				SetFuelConsumptionRateMultiplier(0.0)

				local rpm = math.clamp(tonumber(GetVehicleCurrentRpm(vehicle)) or 0, 0, 1)
				local speedLoad = math.min(GetEntitySpeed(vehicle) / 60.0, 1.0)
				local driveLoad = 0.2 + (rpm * 0.8) + (speedLoad * 0.4)
				newFuel = math.max(fuelAmount - (electricConsumption * profile.consumptionRate * driveLoad), 0)
			else
				local gradeMultiplier = fuelGrades.getConsumptionMultiplier(vehState.fuelPremiumRatio)
				SetFuelConsumptionRateMultiplier(consumptionRate * gradeMultiplier)
				newFuel = GetVehicleFuelLevel(vehicle)
			end

			if fuelAmount > 0 then
				if not electricProfile and GetVehiclePetrolTankHealth(vehicle) < 700 then
					newFuel -= math.random(10, 20) * 0.01
				end

				if fuelAmount ~= newFuel then
					if fuelTick == 15 then
						fuelTick = 0
					end

					fuel.setFuel(vehState, vehicle, newFuel, fuelTick == 0)
					fuelTick += 1
				end
			elseif electricProfile then
				SetVehicleEngineOn(vehicle, false, true, true)
			end
		else
			if not DoesEntityExist(vehicle) then return end
			SetFuelConsumptionRateMultiplier(0.0)
		end
		Wait(1000)
	end

	fuel.setFuel(vehState, vehicle, vehState.fuel, true)
	SetFuelConsumptionRateMultiplier(globalConsumptionRate)
end

if cache.seat == -1 then CreateThread(startDrivingVehicle) end

lib.onCache('seat', function(seat)
	if cache.vehicle then
		state.lastVehicle = cache.vehicle
	end

	if seat == -1 then
		SetTimeout(0, startDrivingVehicle)
	end
end)

local nozzle
local charging = config.electric and config.electric.enabled ~= false and require 'client.charging'

if config.ox_target then
	require 'client.target'

	nozzle = config.nozzle and config.nozzle.enabled and require 'client.nozzle'
else
	RegisterCommand('startfueling', function()
		if state.isFueling or cache.vehicle or lib.progressActive() then return end

		local petrolCan = config.petrolCan.enabled and GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`
		local playerCoords = GetEntityCoords(cache.ped)
		local nearestPump = state.nearestPump

		if nearestPump then
			if petrolCan then
				return fuel.getPetrolCan(nearestPump, true)
			end

			local vehicleInRange = state.lastVehicle and #(GetEntityCoords(state.lastVehicle) - playerCoords) <= 3

			if not vehicleInRange then
				if not config.petrolCan.enabled then return end

				return fuel.getPetrolCan(nearestPump)
			else
				return fuel.startFueling(state.lastVehicle, true)
			end

			return lib.notify({ type = 'error', description = locale('vehicle_far') })
		elseif petrolCan then
			local vehicle = utils.getVehicleInFront()

			if vehicle and DoesVehicleUseFuel(vehicle) then
				if utils.isNearVehiclePetrolCap(vehicle, (config.nozzle and config.nozzle.fuelCapDistance) or 1.8) then
					return fuel.startFueling(vehicle, false)
				end

				return lib.notify({ type = 'error', description = locale('vehicle_far') })
			end
		end
	end)

	RegisterKeyMapping('startfueling', 'Fuel vehicle', 'keyboard', 'e')
	TriggerEvent('chat:removeSuggestion', '/startfueling')
end

exports('portableEvCharger', function(data, item)
	if not charging or not config.electric.portable or config.electric.portable.enabled == false then return end

	exports.ox_inventory:useItem(data, function(usedItem)
		charging.deployPortablePack(usedItem or item)
	end)
end)

if charging and config.electric.portable and config.electric.portable.enabled ~= false then
	pcall(function()
		exports.ox_inventory:displayMetadata({
			{ portableChargePercent = 'Charge (%)' },
			{ portableCharge = 'Energy' },
		})
	end)
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource ~= GetCurrentResourceName() then return end

	local cleanupSteps = {
		{ 'charging state', charging and charging.shutdown },
		{ 'fuel nozzle state', nozzle and nozzle.shutdown },
		{ 'charging station props', chargers.cleanup },
		{ 'custom gas pump props', customPumps.cleanup },
	}

	for i = 1, #cleanupSteps do
		local label = cleanupSteps[i][1]
		local callback = cleanupSteps[i][2]

		if callback then
			local success, message = pcall(callback)

			if not success then
				print(('^1[ox_fuel] Failed to clean up %s during resource stop: %s^0'):format(label, message))
			end
		end
	end
end)
