local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local fuel = require 'client.fuel'
local nozzle = config.nozzle and config.nozzle.enabled and require 'client.nozzle'
local electricProfiles = require 'electric_profiles'
local charging = config.electric and config.electric.enabled ~= false and require 'client.charging'

local pumpOptions = {}
local vehicleOptions = {}
local chargerOptions = {}
local fuelCapDistance = (config.nozzle and config.nozzle.fuelCapDistance) or 1.8
local targetFuelCapDistance = fuelCapDistance + 0.75
local chargePortDistance = (config.electric and config.electric.chargePortDistance) or 1.8
local targetChargePortDistance = chargePortDistance + 0.75

if nozzle then
	pumpOptions[#pumpOptions + 1] = {
		name = 'ox_fuel:takeNozzle',
		distance = 3,
		onSelect = function(data)
			if state.petrolCan then
				return lib.notify({ type = 'error', description = locale('pump_fuel_with_can') })
			end

			nozzle.take(data.entity)
		end,
		icon = 'fas fa-gas-pump',
		label = locale('take_nozzle'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and nozzle.isPumpAvailable(entity)
				and not nozzle.isHolding()
				and (not charging or not charging.isHolding())
				and not state.isFueling
				and not cache.vehicle
				and not lib.progressActive()
		end,
	}

	pumpOptions[#pumpOptions + 1] = {
		name = 'ox_fuel:returnNozzle',
		distance = 3,
		onSelect = function(data)
			nozzle.returnToPump(data.entity)
		end,
		icon = 'fas fa-hand',
		label = locale('return_nozzle'),
		canInteract = function(entity)
			return nozzle.isSourcePump(entity)
				and nozzle.isInHand()
				and not nozzle.isFueling()
				and not state.isFueling
				and not lib.progressActive()
		end,
	}

	pumpOptions[#pumpOptions + 1] = {
		name = 'ox_fuel:fuelOptions',
		distance = 3,
		onSelect = function()
			nozzle.chooseOptions()
		end,
		icon = 'fas fa-sliders',
		label = locale('change_fuel_options'),
		canInteract = function(entity)
			return nozzle.isSourcePump(entity)
				and nozzle.isInHand()
				and not nozzle.isFueling()
				and not state.isFueling
				and not lib.progressActive()
		end,
	}

	vehicleOptions[#vehicleOptions + 1] = {
		name = 'ox_fuel:insertNozzle',
		distance = 2.5,
		onSelect = function(data)
			if not utils.isNearVehiclePetrolCap(data.entity, fuelCapDistance) then
				return lib.notify({ type = 'error', description = locale('vehicle_far') })
			end

			fuel.startFueling(data.entity, true)
		end,
		icon = 'fas fa-gas-pump',
		label = locale('insert_nozzle'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and DoesVehicleUseFuel(entity)
				and not electricProfiles.isElectricModel(GetEntityModel(entity))
				and nozzle.isInHand()
				and nozzle.isInRange()
				and utils.isNearVehiclePetrolCap(entity, targetFuelCapDistance)
				and not state.isFueling
				and not cache.vehicle
				and not lib.progressActive()
		end,
	}

	vehicleOptions[#vehicleOptions + 1] = {
		name = 'ox_fuel:removeNozzle',
		distance = 2.5,
		onSelect = function(data)
			nozzle.detachFromVehicle(data.entity)
		end,
		icon = 'fas fa-hand',
		label = locale('remove_nozzle'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and nozzle.isAttachedToVehicle(entity)
				and not cache.vehicle
		end,
	}
else
	pumpOptions[#pumpOptions + 1] = {
		name = 'ox_fuel:startFueling',
		distance = 4,
		onSelect = function()
			fuel.startFueling(state.lastVehicle, true)
		end,
		icon = 'fas fa-gas-pump',
		label = locale('start_fueling'),
		canInteract = function()
			local vehicle = state.lastVehicle

			if state.isFueling or cache.vehicle or lib.progressActive() then return false end
			if not vehicle or not DoesEntityExist(vehicle) or not DoesVehicleUseFuel(vehicle) then return false end
			if electricProfiles.isElectricModel(GetEntityModel(vehicle)) then return false end

			return #(GetEntityCoords(vehicle) - GetEntityCoords(cache.ped)) <= 3
		end,
	}
end

if config.petrolCan.enabled then
	pumpOptions[#pumpOptions + 1] = {
		name = 'ox_fuel:petrolCanPump',
		distance = 4,
		onSelect = function(data)
			local petrolCan = GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`

			fuel.getPetrolCan(data.entity, petrolCan)
		end,
		icon = 'fas fa-faucet',
		label = locale('petrolcan_buy_or_refill'),
		canInteract = function(entity)
			return not state.isFueling
				and not cache.vehicle
				and not lib.progressActive()
				and (not nozzle or not nozzle.isHolding())
				and (not charging or not charging.isHolding())
				and (not nozzle or nozzle.isPumpAvailable(entity))
		end,
	}

	vehicleOptions[#vehicleOptions + 1] = {
		name = 'ox_fuel:petrolCanVehicle',
		distance = 3,
		onSelect = function(data)
			if not utils.isNearVehiclePetrolCap(data.entity, fuelCapDistance) then
				return lib.notify({ type = 'error', description = locale('vehicle_far') })
			end

			if not state.petrolCan then
				return lib.notify({ type = 'error', description = locale('petrolcan_not_equipped') })
			end

			if state.petrolCan.metadata.ammo <= 0 then
				return lib.notify({
					type = 'error',
					description = locale('petrolcan_not_enough_fuel'),
				})
			end

			fuel.startFueling(data.entity)
		end,
		icon = 'fas fa-gas-pump',
		label = locale('start_fueling'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and DoesVehicleUseFuel(entity)
				and not electricProfiles.isElectricModel(GetEntityModel(entity))
				and state.petrolCan ~= nil
				and utils.isNearVehiclePetrolCap(entity, targetFuelCapDistance)
				and (not nozzle or not nozzle.isHolding())
				and (not charging or not charging.isHolding())
				and not state.isFueling
				and not cache.vehicle
				and not lib.progressActive()
		end,
	}
end

if charging then
	chargerOptions[#chargerOptions + 1] = {
		name = 'ox_fuel:takeChargeConnector',
		distance = 3,
		onSelect = function(data)
			charging.take(data.entity)
		end,
		icon = 'fas fa-bolt',
		label = locale('take_charge_connector'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and charging.isChargerAvailable(entity)
				and not charging.isHolding()
				and (not nozzle or not nozzle.isHolding())
				and not state.isFueling
				and not cache.vehicle
				and not lib.progressActive()
		end,
	}

	chargerOptions[#chargerOptions + 1] = {
		name = 'ox_fuel:returnChargeConnector',
		distance = 3,
		onSelect = function(data)
			charging.returnToCharger(data.entity)
		end,
		icon = 'fas fa-hand',
		label = locale('return_charge_connector'),
		canInteract = function(entity)
			return charging.isSourceCharger(entity)
				and charging.isInHand()
				and not charging.isCharging()
				and not state.isFueling
				and not lib.progressActive()
		end,
	}

	chargerOptions[#chargerOptions + 1] = {
		name = 'ox_fuel:chargeOptions',
		distance = 3,
		onSelect = function()
			charging.chooseOptions()
		end,
		icon = 'fas fa-sliders',
		label = locale('change_charge_options'),
		canInteract = function(entity)
			return charging.isSourceCharger(entity)
				and charging.isInHand()
				and not charging.isCharging()
				and not state.isFueling
				and not lib.progressActive()
		end,
	}

	if config.electric.portable and config.electric.portable.enabled ~= false then
		chargerOptions[#chargerOptions + 1] = {
			name = 'ox_fuel:buyPortableCharger',
			distance = 3,
			onSelect = function(data)
				charging.buyPortable(data.entity)
			end,
			icon = 'fas fa-car-battery',
			label = locale('portable_buy'),
			canInteract = function(entity)
				return (not nozzle or not nozzle.isHolding()) and charging.canBuyPortable(entity)
			end,
		}

		chargerOptions[#chargerOptions + 1] = {
			name = 'ox_fuel:rechargePortableCharger',
			distance = 3,
			onSelect = function(data)
				charging.rechargePortable(data.entity)
			end,
			icon = 'fas fa-battery-half',
			label = locale('portable_recharge'),
			canInteract = function(entity)
				return charging.canRechargePortable(entity)
			end,
		}
	end

	vehicleOptions[#vehicleOptions + 1] = {
		name = 'ox_fuel:startCharging',
		distance = 2.5,
		onSelect = function(data)
			charging.start(data.entity)
		end,
		icon = 'fas fa-bolt',
		label = locale('start_charging'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and charging.isElectricVehicle(entity)
				and charging.isInHand()
				and charging.isInRange()
				and utils.isNearVehiclePetrolCap(entity, targetChargePortDistance)
				and not state.isFueling
				and not cache.vehicle
				and not lib.progressActive()
		end,
	}

	vehicleOptions[#vehicleOptions + 1] = {
		name = 'ox_fuel:removeChargeConnector',
		distance = 2.5,
		onSelect = function(data)
			charging.detachFromVehicle(data.entity)
		end,
		icon = 'fas fa-hand',
		label = locale('remove_charge_connector'),
		canInteract = function(entity)
			return DoesEntityExist(entity)
				and charging.isAttachedToVehicle(entity)
				and not cache.vehicle
		end,
	}
end

exports.ox_target:addModel(config.pumpModels, pumpOptions)

if charging and #chargerOptions > 0 then
	exports.ox_target:addModel(config.electric.chargerModel, chargerOptions)
end

if #vehicleOptions > 0 then
	exports.ox_target:addGlobalVehicle(vehicleOptions)
end
