local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local nozzle = config.ox_target and config.nozzle and config.nozzle.enabled and require 'client.nozzle'
local meter = require 'client.meter'
local checkout = require 'client.checkout'
local chaos = require 'client.chaos'
local electricProfiles = require 'electric_profiles'
local fuel = {}
local fuelingRun = 0
local fuelingSettings = config.fueling or {}
local meterSettings = config.fuelMeter or {}
local activeCanTransaction

local function roundPrice(value)
	value = math.max(tonumber(value) or 0, 0)

	local decimals = math.clamp(math.floor(tonumber(fuelingSettings.priceDecimals) or 0), 0, 2)
	local scale = 10 ^ decimals
	local rounded = math.floor(value * scale + 0.5) / scale

	return value > 0 and math.max(rounded, 1 / scale) or 0
end

function fuel.getMinimumPumpPrice(selection)
	local tickSeconds = math.max(tonumber(config.refillTick) or 500, 1) / 1000
	local firstTickVolume = math.max(tonumber(fuelingSettings.pumpGallonsPerSecond) or 0.20, 0) * tickSeconds
	local pricePerGallon = selection and selection.pricePerGallon or fuelingSettings.pricePerGallon

	return roundPrice(firstTickVolume * math.max(tonumber(pricePerGallon) or 0, 0))
end

local function meterPayload(isPump, initialFuel, fuelAmount, price, canRemaining, tankCapacity, canCapacity, pricePerGallon, selection)
	local tankPercent = math.clamp(fuelAmount, 0, 100)
	local addedPercent = math.max(tankPercent - initialFuel, 0)
	local meterUnit = meter.getUnit()

	local payload = {
		mode = isPump and 'pump' or 'can',
		label = locale(isPump and 'fuel_meter_fueling' or 'fuel_meter_can_fueling'),
		state = 'fueling',
		tankPercent = tankPercent,
		addedVolume = tankCapacity * (addedPercent / 100),
		cost = price or 0,
		canRemainingVolume = canCapacity * (math.clamp(canRemaining or 0, 0, 100) / 100),
		unit = meterUnit,
		unitLabel = locale(meterUnit == 'liters' and 'fuel_meter_liters' or 'fuel_meter_gallons'),
		unitPrice = isPump and meter.getUnitPrice(pricePerGallon) or 0,
		levelLabel = locale('fuel_meter_tank_level'),
		saleLabel = locale('fuel_meter_sale'),
		canLabel = locale('fuel_meter_can_left'),
		addedLabel = locale('fuel_meter_added'),
		gradeLabel = selection and selection.gradeLabel or nil,
		gradeShortLabel = selection and selection.gradeShortLabel or nil,
		paymentLabel = selection and selection.paymentLabel or nil,
		paymentShortLabel = selection and selection.paymentShortLabel or nil,
	}

	return isPump and meter.applyPumpDisplay(payload) or payload
end

local function startFuelingAnimation(isPump)
	local dictionary = isPump and 'timetable@gardener@filling_can' or 'weapon@w_sp_jerrycan'
	local clip = isPump and 'gar_ig_5_filling_can' or 'fire'

	lib.requestAnimDict(dictionary)
	TaskPlayAnim(cache.ped, dictionary, clip, 2.0, 2.0, -1, 49, 0.0, false, false, false)

	return dictionary
end


local function startFuelingControls(runId, onCancel)
	CreateThread(function()
		while state.isFueling and fuelingRun == runId do
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

---@param vehState StateBag
---@param vehicle integer
---@param amount number
---@param replicate? boolean
function fuel.setFuel(vehState, vehicle, amount, replicate)
	if DoesEntityExist(vehicle) then
		amount = math.clamp(amount, 0, 100)

		SetVehicleFuelLevel(vehicle, amount)
		vehState:set('fuel', amount, replicate)
	end
end

local function canTransactionPayload(transaction, progress, label, meterState)
	progress = math.clamp(tonumber(progress) or 0, 0, 1)

	local meterUnit = meter.getUnit()
	local capacity = math.max(tonumber(transaction.capacity) or 0, 0)
	local addedVolume = math.max(tonumber(transaction.addedVolume) or 0, 0)
	local initialVolume = math.max(capacity - addedVolume, 0)
	local currentVolume = math.min(initialVolume + (addedVolume * progress), capacity)
	local tankPercent = capacity > 0 and (currentVolume / capacity) * 100 or nil

	return meter.applyPumpDisplay({
		mode = 'can-transaction',
		label = label,
		state = meterState or 'fueling',
		tankPercent = tankPercent,
		addedVolume = meter.toDisplayVolume(addedVolume * progress),
		cost = transaction.price * progress,
		unit = meterUnit,
		unitLabel = locale(meterUnit == 'liters' and 'fuel_meter_liters' or 'fuel_meter_gallons'),
		unitPrice = meter.getUnitPrice(transaction.pricePerGallon),
		levelLabel = locale('fuel_meter_can_level'),
		saleLabel = locale('fuel_meter_sale'),
		gradeLabel = transaction.gradeLabel,
		gradeShortLabel = transaction.gradeShortLabel,
		paymentLabel = transaction.paymentLabel,
		paymentShortLabel = transaction.paymentShortLabel,
	})
end

function fuel.getPetrolCan(pump, refuel)
	local pumpEntity = type(pump) == 'number' and DoesEntityExist(pump) and pump or nil
	local coords = pumpEntity and GetEntityCoords(pumpEntity) or pump

	if not coords then return end

	meter.setPump(pumpEntity)
	meter.show(meter.readyPayload(checkout.getDefault()))

	local selection = checkout.select(nil, locale(refuel and 'fuelcan_refill_options' or 'fuelcan_buy_options'), true)

	if not selection then
		meter.hide()
		meter.clearPump()
		return
	end

	local pumpModel = pumpEntity and GetEntityModel(pumpEntity) or nil
	local pumpPayload = pumpEntity and { x = coords.x, y = coords.y, z = coords.z } or nil

	TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, config.petrolCan.duration)
	Wait(500)

	local transaction = lib.callback.await(
		'ox_fuel:prepareFuelCan',
		false,
		refuel == true,
		selection.gradeId,
		selection.paymentId,
		pumpModel,
		pumpPayload
	)

	if not transaction then
		meter.clearPump()
		ClearPedTasks(cache.ped)
		return
	end

	state.isFueling = true
	activeCanTransaction = transaction.id

	local startedAt = GetGameTimer()
	local liveLabel = locale(refuel and 'fuel_meter_can_refilling' or 'fuel_meter_can_buying')
	local animationDictionary = startFuelingAnimation(true)
	local canceledByPlayer = false
	local completed = false

	meter.show(canTransactionPayload(transaction, 0, liveLabel))

	fuelingRun = fuelingRun + 1
	local runId = fuelingRun

	startFuelingControls(runId, function()
		canceledByPlayer = true
	end)

	while activeCanTransaction == transaction.id and state.isFueling do
		local progress = math.clamp((GetGameTimer() - startedAt) / transaction.duration, 0, 1)
		meter.update(canTransactionPayload(transaction, progress, liveLabel))

		if progress >= 1 then
			completed = true
			state.isFueling = false
			break
		end

		Wait(math.max(math.floor(tonumber(config.refillTick) or 500), 100))
	end

	activeCanTransaction = nil
	state.isFueling = false
	ClearPedTasks(cache.ped)
	RemoveAnimDict(animationDictionary)

	local result

	if completed and not canceledByPlayer then
		result = lib.callback.await('ox_fuel:finishFuelCan', false, transaction.id)
	else
		TriggerServerEvent('ox_fuel:cancelFuelCan', transaction.id)
	end

	local finalTransaction = result and {
		addedVolume = result.volume,
		capacity = result.capacity,
		price = result.price,
		pricePerGallon = transaction.pricePerGallon,
		gradeLabel = result.gradeLabel,
		gradeShortLabel = result.gradeShortLabel,
		paymentLabel = result.paymentLabel,
		paymentShortLabel = result.paymentShortLabel,
	} or transaction
	local finalPayload = canTransactionPayload(
		finalTransaction,
		result and 1 or 0,
		locale(result and 'fuel_meter_can_ready' or 'fuel_meter_stopped'),
		result and 'complete' or 'stopped'
	)

	finalPayload.completed = result ~= nil
	meter.finish(finalPayload, { lingerMs = meterSettings.canLingerMs })
	meter.clearPump()
end

function fuel.startFueling(vehicle, isPump)
	if electricProfiles.isElectricModel(GetEntityModel(vehicle)) then
		return lib.notify({ type = 'error', description = locale('electric_requires_charger') })
	end

	local vehState = Entity(vehicle).state
	local fuelAmount = vehState.fuel or GetVehicleFuelLevel(vehicle)
	local usesNozzle = isPump and nozzle
	local fuelCapDistance = (config.nozzle and config.nozzle.fuelCapDistance) or 1.8
	local price, moneyAmount = 0
	local selection

	if fuelAmount >= 99.999 then
		return lib.notify({ type = 'error', description = locale('tank_full') })
	end

	if (not isPump or usesNozzle) and not utils.isNearVehiclePetrolCap(vehicle, fuelCapDistance) then
		return lib.notify({ type = 'error', description = locale('vehicle_far') })
	end

	if usesNozzle and not nozzle.isInHand() then
		return lib.notify({ type = 'error', description = locale('nozzle_not_held') })
	end

	if usesNozzle and not nozzle.isInRange() then
		return lib.notify({ type = 'error', description = locale('nozzle_too_far') })
	end

	if isPump then
		selection = usesNozzle and nozzle.getSelection() or checkout.select(nil, locale('fuel_options_title'), true)

		if not selection then return end
	elseif not state.petrolCan then
		return lib.notify({ type = 'error', description = locale('petrolcan_not_equipped') })
	elseif state.petrolCan.metadata.ammo <= 0 then
		return lib.notify({
			type = 'error',
			description = locale('petrolcan_not_enough_fuel')
		})
	end

	state.isFueling = true

	local fuelcapPosition = utils.getVehiclePetrolCapPosition(vehicle)

	if (config.nozzle and config.nozzle.faceFuelCap) ~= false and fuelcapPosition then
		TaskTurnPedToFaceCoord(cache.ped, fuelcapPosition.x, fuelcapPosition.y, fuelcapPosition.z, 500)
	else
		TaskTurnPedToFaceEntity(cache.ped, vehicle, 500)
	end

	Wait(500)

	local nozzleAttached = false

	if usesNozzle then
		if not nozzle.startFueling(vehicle) then
			state.isFueling = false
			ClearPedTasks(cache.ped)
			return
		end

		nozzleAttached = nozzle.isAttachedToVehicle(vehicle)
	end

	local session = lib.callback.await(
		'ox_fuel:startFueling',
		false,
		NetworkGetNetworkIdFromEntity(vehicle),
		isPump == true,
		fuelAmount,
		GetVehicleClass(vehicle),
		selection and selection.gradeId or nil,
		selection and selection.paymentId or nil
	)

	if not session then
		if usesNozzle then nozzle.stopFueling(true) end

		state.isFueling = false
		ClearPedTasks(cache.ped)
		return
	end

	fuelAmount = session.fuel
	local initialFuel = session.fuel
	local initialCanAmount = not isPump and tonumber(state.petrolCan and state.petrolCan.metadata.ammo) or 0
	local completedTicks = 0
	local canRemaining = initialCanAmount
	local completedNaturally = false
	local canceledByPlayer = false
	local animationDictionary = not nozzleAttached and startFuelingAnimation(isPump)
	local tankCapacityGallons = tonumber(session.tankCapacityGallons) or 0
	local tankCapacity = meter.toDisplayVolume(tankCapacityGallons)
	local canCapacityGallons = meter.getCanCapacityGallons()
	local canCapacity = meter.getCanCapacity()
	local volumePerTick = math.max(tonumber(session.volumePerTick) or 0, 0)
	local maxVolume = math.max(tonumber(session.maxVolume) or 0, 0)
	local pricePerGallon = math.max(tonumber(session.pricePerGallon) or 0, 0)
	local transferredVolume = 0
	local vintageQuirk = session.chaosVintageQuirk
	local vintageQuirkTriggered = false

	selection = {
		gradeId = session.gradeId,
		gradeLabel = session.gradeLabel,
		gradeShortLabel = session.gradeShortLabel,
		pricePerGallon = pricePerGallon,
		paymentId = session.paymentId,
		paymentLabel = session.paymentLabel,
		paymentShortLabel = session.paymentShortLabel,
		availableFunds = session.availableFunds,
	}
	moneyAmount = math.max(tonumber(session.availableFunds) or 0, 0)
	local engineOutcome = chaos.handleFuelSession(vehicle, session.chaosEngine)

	if engineOutcome == 'fire' or engineOutcome == 'explosion' then state.isFueling = false end

	if vintageQuirk and vintageQuirk.type == 'slow_flow' then
		lib.notify({ type = 'inform', description = locale('chaos_vintage_slow_flow') })
	end

	fuelingRun = fuelingRun + 1
	local runId = fuelingRun

	if nozzleAttached then
		ClearPedTasks(cache.ped)
	else
		startFuelingControls(runId, function()
			canceledByPlayer = true
		end)
	end

	meter.show(meterPayload(
		isPump,
		initialFuel,
		fuelAmount,
		price,
		canRemaining,
		tankCapacity,
		canCapacity,
		pricePerGallon,
		selection
	))

	while state.isFueling and completedTicks < session.maxTicks do
		if not DoesEntityExist(vehicle) then
			break
		end

		local nextTicks = completedTicks + 1
		local nextVolume = math.min(nextTicks * volumePerTick, maxVolume)
		local nextPrice = isPump and roundPrice(nextVolume * pricePerGallon) or 0

		if isPump then
			if nextPrice > moneyAmount then
				break
			end
		elseif state.petrolCan then
			-- The server limits transfer volume to the equipped can's available fuel.
		else
			break
		end

		completedTicks = nextTicks
		transferredVolume = nextVolume
		price = nextPrice
		fuelAmount = math.min(initialFuel + ((transferredVolume / tankCapacityGallons) * 100), 100.0)
		canRemaining = math.max(initialCanAmount - ((transferredVolume / canCapacityGallons) * 100), 0)

		meter.update(meterPayload(
			isPump,
			initialFuel,
			fuelAmount,
			price,
			canRemaining,
			tankCapacity,
			canCapacity,
			pricePerGallon,
			selection
		))

		if transferredVolume >= maxVolume - 0.0001 or completedTicks >= session.maxTicks then
			completedNaturally = true
			state.isFueling = false
			fuelAmount = math.min(fuelAmount, 100.0)
		end

		if state.isFueling
			and not vintageQuirkTriggered
			and vintageQuirk
			and vintageQuirk.type == 'click_off'
			and completedTicks >= (tonumber(vintageQuirk.triggerTick) or math.huge)
		then
			vintageQuirkTriggered = true
			local pausedPayload = meterPayload(
				isPump,
				initialFuel,
				fuelAmount,
				price,
				canRemaining,
				tankCapacity,
				canCapacity,
				pricePerGallon,
				selection
			)
			pausedPayload.label = locale('chaos_vintage_click_off')
			pausedPayload.state = 'stopped'
			meter.update(pausedPayload)
			lib.notify({ type = 'warning', description = locale('chaos_vintage_click_off') })

			if usesNozzle and nozzle.pauseFueling then
				nozzle.pauseFueling(vintageQuirk.durationMs)
			else
				Wait(math.max(math.floor(tonumber(vintageQuirk.durationMs) or 1500), 250))
			end

			if state.isFueling then
				meter.update(meterPayload(
					isPump,
					initialFuel,
					fuelAmount,
					price,
					canRemaining,
					tankCapacity,
					canCapacity,
					pricePerGallon,
					selection
				))
			end
		end

		Wait(config.refillTick)
	end

	state.isFueling = false

	if usesNozzle then nozzle.stopFueling() end

	if animationDictionary then
		ClearPedTasks(cache.ped)
		RemoveAnimDict(animationDictionary)
	end

	local result = lib.callback.await('ox_fuel:finishFueling', false, session.id, completedTicks)
	local finalFuel = result and result.fuel or initialFuel
	local finalPrice = result and result.price or 0
	local finalCanAmount = result and result.durability or initialCanAmount
	local completed = result and completedNaturally and not canceledByPlayer

	if result then
		selection.gradeLabel = result.gradeLabel or selection.gradeLabel
		selection.gradeShortLabel = result.gradeShortLabel or selection.gradeShortLabel
		selection.paymentLabel = result.paymentLabel or selection.paymentLabel
		selection.paymentShortLabel = result.paymentShortLabel or selection.paymentShortLabel
	end

	local finalMeterPayload = meterPayload(
		isPump,
		initialFuel,
		finalFuel,
		finalPrice,
		finalCanAmount,
		tankCapacity,
		canCapacity,
		pricePerGallon,
		selection
	)
	finalMeterPayload.label = locale(completed and 'fuel_meter_complete' or 'fuel_meter_stopped')
	finalMeterPayload.state = completed and 'complete' or 'stopped'
	finalMeterPayload.completed = completed == true

	meter.finish(finalMeterPayload, {
		hold = usesNozzle and nozzle.isHolding(),
	})
end

return fuel
