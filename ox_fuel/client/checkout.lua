local config = require 'config'
local fuelGrades = require 'fuel_grades'
local meter = require 'client.meter'

local checkout = {}
local paymentSettings = config.payments or {}
local meterSettings = config.fuelMeter or {}
local fuelingSettings = config.fueling or {}
local electricSettings = config.electric or {}

local function defaultPayment()
	local id = type(paymentSettings.defaultMethod) == 'string' and string.lower(paymentSettings.defaultMethod) or 'cash'
	local method = paymentSettings.methods and paymentSettings.methods[id] or {}

	return {
		id = id,
		label = tostring(method.label or id),
		shortLabel = tostring(method.shortLabel or method.label or id):upper(),
		balance = 0,
	}
end

function checkout.getDefault()
	local grade = fuelGrades.resolve(fuelingSettings.defaultGrade)
	local payment = defaultPayment()

	return {
		gradeId = grade.id,
		gradeLabel = grade.label,
		gradeShortLabel = grade.shortLabel,
		pricePerGallon = grade.pricePerGallon,
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		availableFunds = payment.balance,
	}
end

function checkout.getElectricDefault()
	local modeId = type(electricSettings.defaultMode) == 'string' and string.lower(electricSettings.defaultMode) or 'standard'
	local mode = electricSettings.modes and electricSettings.modes[modeId] or {}
	local payment = defaultPayment()

	return {
		modeId = modeId,
		modeLabel = tostring(mode.label or modeId),
		modeShortLabel = tostring(mode.shortLabel or mode.label or modeId):upper(),
		pricePerKwh = math.max(tonumber(mode.pricePerKwh) or 0, 0),
		displayPowerKw = math.max(tonumber(mode.displayPowerKw) or 0, 0),
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		availableFunds = payment.balance,
	}
end

local function findById(values, id)
	for i = 1, #values do
		if values[i].id == id then return values[i] end
	end
end

local function gradeOptionLabel(grade)
	local currency = meterSettings.currency or '$'
	local unit = string.lower(tostring(meterSettings.unit or 'gallons'))
	local price = grade.pricePerGallon
	local unitLabel = 'GAL'

	if unit == 'liters' then
		price = price / 3.785411784
		unitLabel = 'L'
	end

	local mileage = grade.consumptionMultiplier < 0.999
		and (' | %d%% less consumption'):format(math.floor((1 - grade.consumptionMultiplier) * 100 + 0.5))
		or ''

	return ('%s | %s%.2f/%s%s'):format(grade.label, currency, price, unitLabel, mileage)
end

local function paymentOptionLabel(payment)
	local currency = meterSettings.currency or '$'

	return ('%s | %s%.0f available'):format(payment.label, currency, payment.balance)
end

local function nuiPaymentOptions(payments)
	local currency = meterSettings.currency or '$'
	local output = {}

	for i = 1, #payments do
		local payment = payments[i]
		output[i] = {
			id = payment.id,
			label = payment.label,
			shortLabel = payment.shortLabel,
			meta = locale('checkout_available', currency, payment.balance),
		}
	end

	return output
end


local function nuiGradeOptions(grades)
	local currency = meterSettings.currency or '$'
	local displayUnit = string.lower(tostring(meterSettings.unit or 'gallons'))
	local output = {}

	for i = 1, #grades do
		local grade = grades[i]
		local price = grade.pricePerGallon
		local unitLabel = 'GAL'

		if displayUnit == 'liters' then
			price = price / 3.785411784
			unitLabel = 'L'
		end

		local benefit = grade.consumptionMultiplier < 0.999
			and locale('checkout_less_consumption', math.floor((1 - grade.consumptionMultiplier) * 100 + 0.5))
			or nil

		output[i] = {
			id = grade.id,
			label = grade.label,
			shortLabel = grade.shortLabel,
			badge = grade.octane and tostring(math.floor(grade.octane + 0.5)) or grade.shortLabel,
			meta = ('%s%.2f/%s'):format(currency, price, unitLabel),
			benefit = benefit,
		}
	end

	return output
end

local function nuiChargingOptions(modes)
	local currency = meterSettings.currency or '$'
	local output = {}

	for i = 1, #modes do
		local mode = modes[i]
		output[i] = {
			id = mode.id,
			label = mode.label,
			shortLabel = mode.shortLabel,
			meta = ('%s%.2f/kWh'):format(currency, mode.pricePerKwh),
			benefit = mode.displayPowerKw and mode.displayPowerKw > 0
				and ('%.0f kW'):format(mode.displayPowerKw)
				or locale('checkout_charge_rate', mode.kwhPerSecond),
		}
	end

	return output
end

local function selectWithNui(kind, title, primaryLabel, primaryOptions, paymentOptions, primaryId, paymentId)
	local result = meter.selectOptions({
		checkoutType = kind,
		title = title,
		primaryLabel = primaryLabel,
		paymentLabel = locale('payment_method'),
		confirmLabel = locale('checkout_confirm'),
		cancelLabel = locale('checkout_cancel'),
		primaryOptions = primaryOptions,
		paymentOptions = nuiPaymentOptions(paymentOptions),
		primaryId = primaryId,
		paymentId = paymentId,
	})

	return result and { result.primaryId, result.paymentId } or nil
end

function checkout.select(current, title, cancelAction)
	local options = lib.callback.await('ox_fuel:getPurchaseOptions', false)

	if not options or not options.grades or not options.payments or #options.grades == 0 or #options.payments == 0 then
		lib.notify({ type = 'error', description = locale('payment_method_unavailable') })
		return
	end

	current = current or checkout.getDefault()

	local gradeId = findById(options.grades, current.gradeId) and current.gradeId or options.defaultGrade
	local paymentId = findById(options.payments, current.paymentId) and current.paymentId or options.defaultPayment
	local gradeOptions = {}
	local paymentOptions = {}
	local input

	for i = 1, #options.grades do
		local grade = options.grades[i]
		gradeOptions[i] = { value = grade.id, label = gradeOptionLabel(grade) }
	end

	for i = 1, #options.payments do
		local payment = options.payments[i]
		paymentOptions[i] = { value = payment.id, label = paymentOptionLabel(payment) }
	end

	if meter.usesNuiCheckout() then
		input = selectWithNui(
			'fuel',
			title or locale('fuel_options_title'),
			locale('fuel_grade'),
			nuiGradeOptions(options.grades),
			options.payments,
			gradeId,
			paymentId
		)
	else
		input = lib.inputDialog(title or locale('fuel_options_title'), {
		{
			type = 'select',
			label = locale('fuel_grade'),
			icon = 'gas-pump',
			options = gradeOptions,
			default = gradeId,
			required = true,
			clearable = false,
		},
		{
			type = 'select',
			label = locale('payment_method'),
			icon = 'wallet',
			options = paymentOptions,
			default = paymentId,
			required = true,
			clearable = false,
		},
		}, {
			allowCancel = true,
			size = 'sm',
		})
	end

	if not input then
		if cancelAction then return end

		return current
	end

	local grade = findById(options.grades, input[1])
	local payment = findById(options.payments, input[2])

	if not grade or not payment then
		if cancelAction then return end

		return current
	end

	return {
		gradeId = grade.id,
		gradeLabel = grade.label,
		gradeShortLabel = grade.shortLabel,
		pricePerGallon = grade.pricePerGallon,
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		availableFunds = payment.balance,
	}
end

local function chargingModeOptionLabel(mode)
	local currency = meterSettings.currency or '$'

	return ('%s | %s%.2f/kWh'):format(mode.label, currency, mode.pricePerKwh)
end

function checkout.selectElectric(current, title, cancelAction)
	local options = lib.callback.await('ox_fuel:getChargingOptions', false)

	if not options or not options.modes or not options.payments or #options.modes == 0 or #options.payments == 0 then
		lib.notify({ type = 'error', description = locale('payment_method_unavailable') })
		return
	end

	current = current or checkout.getElectricDefault()

	local modeId = findById(options.modes, current.modeId) and current.modeId or options.defaultMode
	local paymentId = findById(options.payments, current.paymentId) and current.paymentId or options.defaultPayment
	local modeOptions = {}
	local paymentOptions = {}
	local input

	for i = 1, #options.modes do
		local mode = options.modes[i]
		modeOptions[i] = { value = mode.id, label = chargingModeOptionLabel(mode) }
	end

	for i = 1, #options.payments do
		local payment = options.payments[i]
		paymentOptions[i] = { value = payment.id, label = paymentOptionLabel(payment) }
	end

	if meter.usesNuiCheckout() then
		input = selectWithNui(
			'electric',
			title or locale('charge_options_title'),
			locale('charge_mode'),
			nuiChargingOptions(options.modes),
			options.payments,
			modeId,
			paymentId
		)
	else
		input = lib.inputDialog(title or locale('charge_options_title'), {
		{
			type = 'select',
			label = locale('charge_mode'),
			icon = 'bolt',
			options = modeOptions,
			default = modeId,
			required = true,
			clearable = false,
		},
		{
			type = 'select',
			label = locale('payment_method'),
			icon = 'wallet',
			options = paymentOptions,
			default = paymentId,
			required = true,
			clearable = false,
		},
		}, {
			allowCancel = true,
			size = 'sm',
		})
	end

	if not input then
		if cancelAction then return end

		return current
	end

	local mode = findById(options.modes, input[1])
	local payment = findById(options.payments, input[2])

	if not mode or not payment then
		if cancelAction then return end

		return current
	end

	return {
		modeId = mode.id,
		modeLabel = mode.label,
		modeShortLabel = mode.shortLabel,
		pricePerKwh = mode.pricePerKwh,
		displayPowerKw = math.max(tonumber(mode.displayPowerKw) or 0, 0),
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		availableFunds = payment.balance,
	}
end

function checkout.selectPortablePurchase(title)
	local options = lib.callback.await('ox_fuel:getPortablePurchaseOptions', false)

	if not options or not options.payments or #options.payments == 0 then
		lib.notify({ type = 'error', description = locale('payment_method_unavailable') })
		return
	end

	local paymentId = findById(options.payments, options.defaultPayment) and options.defaultPayment or options.payments[1].id
	local currency = meterSettings.currency or '$'
	local input

	if meter.usesNuiCheckout() then
		input = selectWithNui(
			'electric',
			title or locale('portable_buy_options'),
			locale('portable_product'),
			{
				{
					id = 'portable',
					label = locale('portable_product'),
					shortLabel = locale('portable_pack_short'),
					meta = ('%s%.2f'):format(currency, math.max(tonumber(options.price) or 0, 0)),
					benefit = ('%.1f kWh'):format(math.max(tonumber(options.capacityKwh) or 0, 0)),
				},
			},
			options.payments,
			'portable',
			paymentId
		)
	else
		local paymentOptions = {}

		for i = 1, #options.payments do
			local payment = options.payments[i]
			paymentOptions[i] = { value = payment.id, label = paymentOptionLabel(payment) }
		end

		local selected = lib.inputDialog(title or locale('portable_buy_options'), {
			{
				type = 'select',
				label = locale('payment_method'),
				icon = 'wallet',
				options = paymentOptions,
				default = paymentId,
				required = true,
				clearable = false,
			},
		}, {
			allowCancel = true,
			size = 'sm',
		})

		input = selected and { 'portable', selected[1] } or nil
	end

	if not input then return end

	local payment = findById(options.payments, input[2])

	if not payment then return end

	return {
		price = math.max(tonumber(options.price) or 0, 0),
		capacityKwh = math.max(tonumber(options.capacityKwh) or 0, 0),
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		availableFunds = payment.balance,
	}
end

function checkout.cancel(hideImmediately)
	meter.cancelOptions(hideImmediately == true)
	lib.closeInputDialog()
end

return checkout
