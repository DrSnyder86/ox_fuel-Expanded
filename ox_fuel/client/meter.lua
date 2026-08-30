local config = require 'config'
local vehicleProfiles = require 'vehicle_profiles'
local settings = config.fuelMeter or {}
local fuelingSettings = config.fueling or {}
local meter = {}

local generation = 0
local unit = string.lower(tostring(settings.unit or 'gallons')) == 'liters' and 'liters' or 'gallons'
local activePumpDisplay
local pendingCheckout

function meter.toDisplayVolume(gallons)
	return unit == 'liters' and vehicleProfiles.gallonsToLiters(gallons) or gallons
end

function meter.getUnit()
	return unit
end

function meter.getTankCapacity(vehicle)
	local profile = vehicleProfiles.resolve(GetEntityModel(vehicle), GetVehicleClass(vehicle))

	return meter.toDisplayVolume(profile.tankCapacityGallons)
end

function meter.getCanCapacityGallons()
	local capacity = tonumber(config.petrolCan and config.petrolCan.capacityGallons) or 5.3

	return capacity > 0 and capacity or 5.3
end

function meter.getCanCapacity()
	return meter.toDisplayVolume(meter.getCanCapacityGallons())
end

function meter.getUnitPrice(pricePerGallon)
	pricePerGallon = math.max(tonumber(pricePerGallon) or tonumber(fuelingSettings.pricePerGallon) or 0, 0)

	return unit == 'liters' and pricePerGallon / 3.785411784 or pricePerGallon
end

function meter.setPump(pump)
	if not pump or not DoesEntityExist(pump) then
		activePumpDisplay = nil
		return
	end

	local displays = settings.pumpDisplays or {}
	activePumpDisplay = displays[GetEntityModel(pump)]
end

function meter.clearPump()
	activePumpDisplay = nil
end

function meter.applyPumpDisplay(data)
	local display = activePumpDisplay

	data.theme = data.theme or (display and display.theme == 'vintage' and 'vintage' or 'modern')
	data.variant = data.variant or (display and tostring(display.variant or '') or '')
	data.brand = data.brand or (display and tostring(display.brand or '') or '')
	data.logo = data.logo or (display and tostring(display.logo or '') or '')
	data.accent = data.accent or (display and display.accent or nil)

	return data
end

function meter.readyPayload(selection)
	selection = selection or {}

	return meter.applyPumpDisplay({
		mode = 'pump',
		label = locale('fuel_meter_ready'),
		state = 'ready',
		addedVolume = 0,
		cost = 0,
		unit = unit,
		unitLabel = locale(unit == 'liters' and 'fuel_meter_liters' or 'fuel_meter_gallons'),
		unitPrice = meter.getUnitPrice(selection.pricePerGallon),
		levelLabel = locale('fuel_meter_tank_level'),
		saleLabel = locale('fuel_meter_sale'),
		gradeLabel = selection.gradeLabel,
		gradeShortLabel = selection.gradeShortLabel,
		paymentLabel = selection.paymentLabel,
		paymentShortLabel = selection.paymentShortLabel,
	})
end

function meter.chargingReadyPayload(selection)
	selection = selection or {}

	return meter.applyPumpDisplay({
		mode = 'charging',
		label = locale('charge_meter_ready'),
		state = 'ready',
		addedVolume = 0,
		cost = 0,
		unit = 'kilowatt-hours',
		unitLabel = locale('charge_meter_kwh'),
		unitPrice = math.max(tonumber(selection.pricePerKwh) or 0, 0),
		powerKw = math.max(tonumber(selection.displayPowerKw) or 0, 0),
		levelLabel = locale('charge_meter_battery'),
		saleLabel = locale('charge_meter_sale'),
		energyLabel = locale('charge_meter_energy'),
		rateLabel = locale('charge_meter_rate'),
		powerLabel = locale('charge_meter_power'),
		timeLabel = locale('charge_meter_time'),
		costLabel = locale('charge_meter_cost'),
		gradeLabel = selection.modeLabel,
		gradeShortLabel = selection.modeShortLabel,
		paymentLabel = selection.paymentLabel,
		paymentShortLabel = selection.paymentShortLabel,
	})
end

local function send(action, data)
	if settings.enabled == false then return end

	data = data or {}
	data.action = action
	data.currency = settings.currency or '$'

	SendNUIMessage(data)
end

local function releaseNuiFocus()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
end

local function resolveCheckout(result, hideImmediately)
	local pending = pendingCheckout

	if not pending then return false end

	pendingCheckout = nil
	releaseNuiFocus()
	if not hideImmediately then send('closeOptions') end
	pending:resolve(result)

	return true
end

function meter.usesNuiCheckout()
	return settings.enabled ~= false and string.lower(tostring(settings.checkout or 'nui')) == 'nui'
end

function meter.selectOptions(data)
	if not meter.usesNuiCheckout() then return end

	if pendingCheckout then resolveCheckout(false) end

	local pending = promise.new()
	pendingCheckout = pending
	data = meter.applyPumpDisplay(data or {})
	send('options', data)
	SetNuiFocus(true, true)
	SetNuiFocusKeepInput(false)

	local result = Citizen.Await(pending)

	return type(result) == 'table' and result or nil
end

function meter.cancelOptions(hideImmediately)
	return resolveCheckout(false, hideImmediately == true)
end

RegisterNUICallback('checkoutSubmit', function(data, callback)
	callback({ ok = resolveCheckout(type(data) == 'table' and data or false) })
end)

RegisterNUICallback('checkoutCancel', function(_, callback)
	callback({ ok = resolveCheckout(false) })
end)

function meter.show(data)
	generation = generation + 1
	send('show', data)
end

function meter.update(data)
	send('update', data)
end

function meter.finish(data, options)
	generation = generation + 1
	options = options or {}

	local finishGeneration = generation

	send('finish', data)

	if options.hold then return end

	CreateThread(function()
		Wait(math.max(tonumber(options.lingerMs) or tonumber(settings.lingerMs) or 900, 0))

		if generation == finishGeneration then
			if options.resumeData then
				generation = generation + 1
				send('show', options.resumeData)
			else
				send('hide')
			end
		end
	end)
end

function meter.hide()
	generation = generation + 1
	meter.cancelOptions(true)
	send('hide')
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource == GetCurrentResourceName() then
		meter.hide()
	end
end)

return meter
