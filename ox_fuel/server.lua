local config = require 'config'
local fuelGrades = require 'fuel_grades'
local vehicleProfiles = require 'vehicle_profiles'
local electricProfiles = require 'electric_profiles'

if not config then return end

if config.versionCheck then lib.versionCheck('communityox/ox_fuel') end

local ox_inventory = exports.ox_inventory
local fuelingSettings = config.fueling or {}
local paymentSettings = config.payments or {}
local electricSettings = config.electric or {}
local portableSettings = electricSettings.portable or {}
local nozzleSettings = config.nozzle or {}
local customPumpPropSettings = config.customGasPumpProps or {}
local chaosSettings = config.chaosMode or {}

local function roundPrice(value)
	value = math.max(tonumber(value) or 0, 0)

	local decimals = math.clamp(math.floor(tonumber(fuelingSettings.priceDecimals) or 0), 0, 2)
	local scale = 10 ^ decimals
	local rounded = math.floor(value * scale + 0.5) / scale

	return value > 0 and math.max(rounded, 1 / scale) or 0
end

local function setFuelState(netId, fuel, premiumRatio)
	local vehicle = NetworkGetEntityFromNetworkId(netId)

	if vehicle == 0 or GetEntityType(vehicle) ~= 2 then
		return false
	end

	local state = Entity(vehicle)?.state
	fuel = math.clamp(tonumber(fuel) or 0, 0, 100)

	state:set('fuel', fuel, true)

	if premiumRatio ~= nil then
		state:set('fuelPremiumRatio', fuelGrades.clampRatio(premiumRatio), true)
	end

	return true
end

local customPaymentProvider
local legacyPaymentMethod

local function getQboxBankBalance(playerId)
	if GetResourceState('qbx_core') ~= 'started' then return end

	local success, balance = pcall(function()
		return exports.qbx_core:GetMoney(playerId, 'bank')
	end)

	return success and tonumber(balance) or nil
end

local function chargeQboxBank(playerId, amount)
	if GetResourceState('qbx_core') ~= 'started' then return end

	local success, paid = pcall(function()
		return exports.qbx_core:RemoveMoney(playerId, 'bank', amount, 'fuel purchase')
	end)

	return success and paid == true or false
end

local function getQbBankBalance(playerId)
	if GetResourceState('qb-core') ~= 'started' then return end

	local success, balance = pcall(function()
		local core = exports['qb-core']:GetCoreObject()
		local player = core.Functions.GetPlayer(playerId)

		return player and player.Functions.GetMoney('bank')
	end)

	return success and tonumber(balance) or nil
end

local function chargeQbBank(playerId, amount)
	if GetResourceState('qb-core') ~= 'started' then return end

	local success, paid = pcall(function()
		local core = exports['qb-core']:GetCoreObject()
		local player = core.Functions.GetPlayer(playerId)

		return player and player.Functions.RemoveMoney('bank', amount, 'fuel purchase')
	end)

	return success and paid == true or false
end

local function getEsxBankBalance(playerId)
	if GetResourceState('es_extended') ~= 'started' then return end

	local success, balance = pcall(function()
		local esx = exports.es_extended:getSharedObject()
		local player = esx.GetPlayerFromId(playerId)
		local account = player and player.getAccount('bank')

		return account and account.money
	end)

	return success and tonumber(balance) or nil
end

local function chargeEsxBank(playerId, amount)
	if GetResourceState('es_extended') ~= 'started' then return end

	local balance = getEsxBankBalance(playerId)

	if not balance or balance < amount then return false end

	local success = pcall(function()
		local esx = exports.es_extended:getSharedObject()
		local player = esx.GetPlayerFromId(playerId)

		player.removeAccountMoney('bank', amount, 'fuel purchase')
	end)

	return success
end

local function getPaymentBalance(playerId, methodId)
	if customPaymentProvider and type(customPaymentProvider.getBalance) == 'function' then
		local success, balance = pcall(customPaymentProvider.getBalance, playerId, methodId)

		if success and balance ~= nil then return math.max(tonumber(balance) or 0, 0) end
	end

	if methodId == 'cash' then
		return math.max(tonumber(ox_inventory:GetItemCount(playerId, 'money')) or 0, 0)
	end

	if methodId == 'bank' then
		return getQboxBankBalance(playerId) or getQbBankBalance(playerId) or getEsxBankBalance(playerId)
	end
end

local function chargePayment(playerId, amount, methodId)
	amount = math.max(tonumber(amount) or 0, 0)

	if amount <= 0 then return true end

	if legacyPaymentMethod then
		local success, paid = pcall(legacyPaymentMethod, playerId, amount, methodId)

		return success and paid == true
	end

	if customPaymentProvider and type(customPaymentProvider.pay) == 'function' then
		local success, paid = pcall(customPaymentProvider.pay, playerId, amount, methodId)

		if success and paid ~= nil then return paid == true end
	end

	if methodId == 'cash' then
		return ox_inventory:RemoveItem(playerId, 'money', amount) == true
	end

	if methodId == 'bank' then
		return chargeQboxBank(playerId, amount) or chargeQbBank(playerId, amount) or chargeEsxBank(playerId, amount) or false
	end

	return false
end

local function getPaymentMethod(methodId)
	methodId = type(methodId) == 'string' and string.lower(methodId) or nil

	local methods = paymentSettings.methods or {}
	local method = methodId and methods[methodId] or nil

	if type(method) ~= 'table' or method.enabled == false then return end

	return {
		id = methodId,
		label = tostring(method.label or methodId),
		shortLabel = tostring(method.shortLabel or method.label or methodId):upper(),
	}
end

local function getPaymentMethods(playerId)
	local output = {}
	local seen = {}
	local order = paymentSettings.methodOrder or {}
	local methods = paymentSettings.methods or {}

	local function append(id)
		if seen[id] then return end

		local method = getPaymentMethod(id)
		local balance = method and getPaymentBalance(playerId, id)

		if method and balance ~= nil then
			seen[id] = true
			method.balance = balance
			output[#output + 1] = method
		end
	end

	for i = 1, #order do
		if type(order[i]) == 'string' then append(string.lower(order[i])) end
	end

	for id in pairs(methods) do
		if type(id) == 'string' then append(string.lower(id)) end
	end

	return output
end

local function resolvePayment(playerId, methodId)
	local method = getPaymentMethod(methodId)
	local balance = method and getPaymentBalance(playerId, method.id)

	if not method or balance == nil then
		TriggerClientEvent('ox_lib:notify', playerId, {
			type = 'error',
			description = locale('payment_method_unavailable'),
		})
		return
	end

	method.balance = balance

	return method
end

exports('setPaymentMethod', function(fn)
	legacyPaymentMethod = fn
end)

exports('setPaymentProvider', function(provider, pay)
	if type(provider) == 'function' and type(pay) == 'function' then
		provider = { getBalance = provider, pay = pay }
	end

	if provider ~= nil and (type(provider) ~= 'table' or type(provider.getBalance) ~= 'function' or type(provider.pay) ~= 'function') then
		error('Payment provider must contain getBalance and pay functions.')
	end

	customPaymentProvider = provider
end)

local soundCounter = 0
local activeLoopSounds = {}

local function positionFromPayload(position)
	if type(position) ~= 'table' then return end

	local x = tonumber(position.x or position[1])
	local y = tonumber(position.y or position[2])
	local z = tonumber(position.z or position[3])

	if not x or not y or not z then return end

	return { x = x, y = y, z = z }
end

local function playerPosition(playerId)
	local ped = GetPlayerPed(playerId)

	if not ped or ped == 0 then return end

	local coords = GetEntityCoords(ped)

	return { x = coords.x, y = coords.y, z = coords.z }
end

local function getConfiguredSound(soundName)
	local nozzleSound = config.nozzle and config.nozzle.sounds and config.nozzle.sounds[soundName]

	if nozzleSound then return nozzleSound, config.nozzle end

	local chargingSound = electricSettings.sounds and electricSettings.sounds[soundName]

	if chargingSound then return chargingSound, electricSettings end
end

local function soundUrl(sound, sourceSettings)
	if sound.url then return sound.url end

	local baseUrl = sourceSettings.soundBaseUrl or 'https://cfx-nui-san_andreas_sound/web/sounds/%s.ogg'

	return baseUrl:format(sound.name)
end

local function distanceBetween(a, b)
	if not a or not b then return 0.0 end

	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z

	return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local occupancySettings = config.pumpOccupancy or {}
local pumpLeases = {}
local pumpLeaseCounter = 0
local allowedPumpModels = {}
local gasPumpModels = {}
local destroyedChargers = {}

for i = 1, #config.pumpModels do
	allowedPumpModels[tostring(config.pumpModels[i])] = true
	gasPumpModels[tostring(config.pumpModels[i])] = true
end

if electricSettings.enabled ~= false and electricSettings.chargerModel then
	allowedPumpModels[tostring(electricSettings.chargerModel)] = true
end

local function quantizeCoordinate(value)
	local precision = math.max(math.floor(tonumber(occupancySettings.coordinatePrecision) or 10), 1)
	local scaled = value * precision

	return scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)
end

local function getChargerLocationIndex(position)
	if not position then return end

	local locations = electricSettings.chargerLocations or {}

	for i = 1, #locations do
		local entry = locations[i]
		local location = entry.location or entry

		if location and distanceBetween(position, location) <= 1.0 then return i end
	end
end

local function getPumpKey(model, position)
	model = tonumber(model)

	if not model or model % 1 ~= 0 then return end
	model = math.floor(model)
	if not allowedPumpModels[tostring(model)] then return end
	if not position or math.abs(position.x) > 20000 or math.abs(position.y) > 20000 or math.abs(position.z) > 20000 then return end

	if electricSettings.enabled ~= false and model == tonumber(electricSettings.chargerModel) then
		local index = getChargerLocationIndex(position)

		if not index or destroyedChargers[index] then return end
	end

	return ('%s:%s:%s:%s'):format(
		model,
		quantizeCoordinate(position.x),
		quantizeCoordinate(position.y),
		quantizeCoordinate(position.z)
	)
end

local function broadcastPumpLease(key, owner)
	TriggerClientEvent('ox_fuel:pumpOccupancyChanged', -1, key, owner or false)
end

local function releasePumpLease(key, playerId, token)
	local lease = pumpLeases[key]

	if not lease then return false end
	if playerId and lease.owner ~= playerId then return false end
	if token and lease.token ~= token then return false end

	pumpLeases[key] = nil
	broadcastPumpLease(key)

	return true
end

local function releasePlayerPumps(playerId)
	local keys = {}

	for key, lease in pairs(pumpLeases) do
		if lease.owner == playerId then
			keys[#keys + 1] = key
		end
	end

	for i = 1, #keys do
		releasePumpLease(keys[i], playerId)
	end
end

local function clearExpiredPumpLeases()
	local now = GetGameTimer()
	local keys = {}

	for key, lease in pairs(pumpLeases) do
		if now > lease.expiresAt then
			keys[#keys + 1] = key
		end
	end

	for i = 1, #keys do
		releasePumpLease(keys[i])
	end
end

local function getPlayerActivePumpLease(playerId, model)
	if occupancySettings.enabled == false then return { position = playerPosition(playerId) } end

	clearExpiredPumpLeases()

	local prefix = ('%s:'):format(model)

	for key, lease in pairs(pumpLeases) do
		if lease.owner == playerId and key:sub(1, #prefix) == prefix then
			return lease, key
		end
	end
end

local function getPlayerActiveGasPumpLease(playerId)
	if occupancySettings.enabled == false then return end

	clearExpiredPumpLeases()

	for key, lease in pairs(pumpLeases) do
		if lease.owner == playerId and gasPumpModels[tostring(lease.model)] then
			return lease, key
		end
	end
end

lib.callback.register('ox_fuel:getPumpOccupancy', function()
	if occupancySettings.enabled == false then return {} end

	clearExpiredPumpLeases()

	local occupied = {}

	for key, lease in pairs(pumpLeases) do
		occupied[key] = lease.owner
	end

	return occupied
end)

lib.callback.register('ox_fuel:acquirePump', function(source, model, payload)
	if occupancySettings.enabled == false then return { disabled = true } end

	local position = positionFromPayload(payload)
	local playerPos = playerPosition(source)
	local maxDistance = tonumber(occupancySettings.maxAcquireDistance) or 4.0

	if not position or not playerPos or distanceBetween(playerPos, position) > maxDistance then return end

	local key = getPumpKey(model, position)

	if not key then return end

	local now = GetGameTimer()
	local lease = pumpLeases[key]

	if lease and now > lease.expiresAt then
		releasePumpLease(key)
		lease = nil
	end

	local leaseDuration = math.max(tonumber(occupancySettings.leaseDurationMs) or 15000, 3000)

	if lease then
		if lease.owner ~= source then return end

		pumpLeaseCounter = pumpLeaseCounter + 1
		lease.token = ('%s:%s'):format(source, pumpLeaseCounter)
		lease.expiresAt = now + leaseDuration
		lease.position = position
		lease.model = math.floor(tonumber(model))

		return { key = key, token = lease.token, owner = source }
	end

	pumpLeaseCounter = pumpLeaseCounter + 1
	lease = {
		owner = source,
		token = ('%s:%s'):format(source, pumpLeaseCounter),
		expiresAt = now + leaseDuration,
		position = position,
		model = math.floor(tonumber(model)),
	}
	pumpLeases[key] = lease
	broadcastPumpLease(key, source)

	return { key = key, token = lease.token, owner = source }
end)

RegisterNetEvent('ox_fuel:heartbeatPump', function(key, token)
	local lease = type(key) == 'string' and pumpLeases[key] or nil
	local now = GetGameTimer()

	if not lease or lease.owner ~= source or lease.token ~= token or now > lease.expiresAt then
		if lease and now > lease.expiresAt then releasePumpLease(key) end
		return TriggerClientEvent('ox_fuel:pumpLeaseLost', source, key, token)
	end

	local leaseDuration = math.max(tonumber(occupancySettings.leaseDurationMs) or 15000, 3000)
	lease.expiresAt = now + leaseDuration
end)

RegisterNetEvent('ox_fuel:releasePump', function(key, token)
	if type(key) ~= 'string' or type(token) ~= 'string' then return end

	releasePumpLease(key, source, token)
end)

local destroyedCustomPumps = {}

local function getCustomPumpEntry(index)
	index = tonumber(index)

	if not index or index % 1 ~= 0 then return end

	local entry = config.customGasPumpLocations and config.customGasPumpLocations[index]
	local location = entry and (entry.location or entry)
	local prop = entry and entry.prop
	local model = type(prop) == 'string' and joaat(prop) or tonumber(prop)

	if not entry or not location or not model then return end

	local damageable = entry.damageable

	if damageable == nil then damageable = customPumpPropSettings.damageable ~= false end

	return entry, location, model, damageable == true
end

local function markCustomPumpDestroyed(index, origin)
	if destroyedCustomPumps[index] then return false end

	local _, location, model, damageable = getCustomPumpEntry(index)

	if not damageable then return false end

	destroyedCustomPumps[index] = true

	local pumpKey = getPumpKey(model, location)

	if pumpKey then releasePumpLease(pumpKey) end

	TriggerClientEvent('ox_fuel:explodeCustomPump', -1, index, origin or 0)

	return true, pumpKey
end

lib.callback.register('ox_fuel:getDestroyedCustomPumps', function()
	local destroyed = {}

	for index in pairs(destroyedCustomPumps) do
		destroyed[#destroyed + 1] = index
	end

	return destroyed
end)

RegisterNetEvent('ox_fuel:customPumpDestroyed', function(index)
	if customPumpPropSettings.synchronizeExplosions == false then return end

	index = tonumber(index)

	if not index or index % 1 ~= 0 or destroyedCustomPumps[index] then return end

	local _, location, _, damageable = getCustomPumpEntry(index)
	local position = playerPosition(source)
	local reportDistance = math.max(tonumber(customPumpPropSettings.reportDistance) or 100.0, 1.0)

	if not damageable or not location or not position or distanceBetween(position, location) > reportDistance then return end

	markCustomPumpDestroyed(index, source)
end)

lib.callback.register('ox_fuel:getDestroyedChargers', function()
	local destroyed = {}

	for index in pairs(destroyedChargers) do
		destroyed[#destroyed + 1] = index
	end

	return destroyed
end)

RegisterNetEvent('ox_fuel:chargerDestroyed', function(index)
	local damageSettings = electricSettings.damageEffects or {}

	if electricSettings.enabled == false or damageSettings.enabled == false or damageSettings.synchronize == false then return end

	index = tonumber(index)

	if not index or index % 1 ~= 0 or destroyedChargers[index] then return end

	local entry = electricSettings.chargerLocations and electricSettings.chargerLocations[index]
	local location = entry and (entry.location or entry)
	local position = playerPosition(source)
	local reportDistance = math.max(tonumber(damageSettings.reportDistance) or 100.0, 1.0)
	local damageable = entry and entry.damageable

	if damageable == nil then damageable = damageSettings.damageable ~= false end
	if damageSettings.enabled == false then damageable = false end

	if not damageable or not location or not position or distanceBetween(position, location) > reportDistance then return end

	local pumpKey = getPumpKey(electricSettings.chargerModel, location)
	destroyedChargers[index] = true

	if pumpKey then releasePumpLease(pumpKey) end

	TriggerClientEvent('ox_fuel:destroyCharger', -1, index, source)
end)

if occupancySettings.enabled ~= false then
	CreateThread(function()
		local interval = math.max(math.floor((tonumber(occupancySettings.leaseDurationMs) or 15000) / 3), 1000)

		while true do
			Wait(interval)
			clearExpiredPumpLeases()
		end
	end)
end

local validation = config.serverValidation or {}
local fuelingSessions = {}
local chargingSessions = {}
local fuelCanSessions = {}
local portableChargingSessions = {}
local portableRechargeSessions = {}
local portablePurchaseSessions = {}
local portableDeployments = {}
local fuelingSessionCounter = 0
local chargingSessionCounter = 0
local portableSessionCounter = 0
local chaosCooldowns = {}

local function getChaosFeature(name)
	local feature = chaosSettings[name]

	if chaosSettings.enabled ~= true or type(feature) ~= 'table' or feature.enabled == false then return end

	return feature
end

local function rollChaos(chance)
	chance = math.clamp(tonumber(chance) or 0, 0, 100)

	return chance > 0 and math.random() * 100 < chance
end

local function chaosLog(playerId, eventName, detail)
	if chaosSettings.adminLogging ~= true then return end

	local name = GetPlayerName(playerId) or 'unknown'
	print(('[ox_fuel] Chaos Mode: %s (%s) triggered %s%s.'):format(
		name,
		playerId,
		eventName,
		detail and (' - ' .. detail) or ''
	))
end

local function canTriggerMajorChaos(playerId, session)
	local protections = chaosSettings.protections or {}

	if protections.oneMajorEventPerSession ~= false and session and session.chaosMajor then return false end

	return GetGameTimer() >= (chaosCooldowns[playerId] or 0)
end

local function markMajorChaos(playerId, session, eventName, detail)
	local cooldownSeconds = math.max(tonumber(chaosSettings.protections and chaosSettings.protections.playerCooldownSeconds) or 900, 0)

	if session then session.chaosMajor = true end
	chaosCooldowns[playerId] = GetGameTimer() + math.floor(cooldownSeconds * 1000)
	chaosLog(playerId, eventName, detail)
end

local function isEngineRunning(vehicle)
	if type(GetIsVehicleEngineRunning) ~= 'function' then return false end

	local success, running = pcall(GetIsVehicleEngineRunning, vehicle)

	return success and running == true
end

local function isListedChaosModel(models, model)
	if type(models) ~= 'table' then return false end

	for key, value in pairs(models) do
		local configured = type(value) == 'boolean' and key or value
		configured = type(configured) == 'string' and joaat(configured) or tonumber(configured)

		if configured == model then return true end
	end

	return false
end

local function getChaosFaultTick(maxTicks, feature)
	if maxTicks <= 2 then return end

	local minimum = math.clamp(tonumber(feature.progressMin) or 0.35, 0.05, 0.95)
	local maximum = math.clamp(tonumber(feature.progressMax) or 0.80, minimum, 0.95)
	local progress = minimum + (math.random() * (maximum - minimum))

	return math.clamp(math.floor(maxTicks * progress + 0.5), 1, maxTicks - 1)
end

local function resolveEngineChaos(playerId, vehicle, session)
	local feature = getChaosFeature('engineRunning')

	if not feature or not isEngineRunning(vehicle) then return end

	local result = { warning = feature.warnPlayer ~= false }

	if canTriggerMajorChaos(playerId, session) and rollChaos(feature.explosionChance) then
		result.outcome = {
			type = 'explosion',
			explosionType = math.floor(tonumber(feature.explosionType) or 6),
			damageScale = math.max(tonumber(feature.damageScale) or 0.65, 0),
			cameraShake = math.max(tonumber(feature.cameraShake) or 0.5, 0),
		}
		markMajorChaos(playerId, session, 'engine-running explosion')
	elseif canTriggerMajorChaos(playerId, session) and rollChaos(feature.fireChance) then
		result.outcome = {
			type = 'fire',
			engineDamage = math.max(tonumber(feature.engineDamage) or 250.0, 0),
			bodyDamage = math.max(tonumber(feature.bodyDamage) or 100.0, 0),
			fireDurationMs = math.max(math.floor(tonumber(feature.fireDurationMs) or 7000), 500),
		}
		markMajorChaos(playerId, session, 'engine-running fire')
	elseif rollChaos(feature.stallChance) then
		result.outcome = { type = 'stall' }
		chaosLog(playerId, 'engine stall')
	end

	return result
end

local function resolveVintagePumpQuirk(model, maxTicks)
	local feature = getChaosFeature('vintagePumpQuirks')

	if not feature or not isListedChaosModel(feature.models, model) then return end

	if rollChaos(feature.clickOffChance) then
		return {
			type = 'click_off',
			durationMs = math.max(math.floor(tonumber(feature.clickOffDurationMs) or 1500), 250),
			triggerTick = getChaosFaultTick(maxTicks, {
				progressMin = feature.clickOffProgressMin,
				progressMax = feature.clickOffProgressMax,
			}),
		}
	end

	if rollChaos(feature.slowFlowChance) then
		return {
			type = 'slow_flow',
			flowMultiplier = math.clamp(tonumber(feature.flowMultiplier) or 0.55, 0.1, 1.0),
		}
	end
end

local function resolveChargingFault(playerId, session, featureName, faultType)
	local feature = getChaosFeature(featureName)

	if not feature or not canTriggerMajorChaos(playerId, session) or not rollChaos(feature.shutdownChance) then return end

	local faultTick = getChaosFaultTick(session.maxTicks, feature)

	if not faultTick then return end

	markMajorChaos(playerId, session, faultType == 'portable_thermal' and 'portable thermal shutdown' or 'rapid-charge fault')

	return { type = faultType, faultTick = faultTick }
end

local function hasActiveSession(playerId)
	return fuelingSessions[playerId]
		or chargingSessions[playerId]
		or fuelCanSessions[playerId]
		or portableChargingSessions[playerId]
		or portableRechargeSessions[playerId]
		or portablePurchaseSessions[playerId]
end

local function notifyPlayer(playerId, description)
	TriggerClientEvent('ox_lib:notify', playerId, {
		type = 'error',
		description = description,
	})
end

local function validateFuelingVehicle(playerId, netId, expectedVehicle, skipPlayerDistance)
	netId = tonumber(netId)

	if not netId or netId <= 0 or netId % 1 ~= 0 then return end

	local vehicle = NetworkGetEntityFromNetworkId(netId)

	if vehicle == 0 or GetEntityType(vehicle) ~= 2 then return end
	if expectedVehicle and vehicle ~= expectedVehicle then return end

	if skipPlayerDistance then return vehicle, netId end

	local ped = GetPlayerPed(playerId)

	if not ped or ped == 0 then return end

	local playerCoords = GetEntityCoords(ped)
	local vehicleCoords = GetEntityCoords(vehicle)
	local maxDistance = tonumber(validation.maxVehicleDistance) or 6.0

	if distanceBetween(playerCoords, vehicleCoords) > maxDistance then return end

	return vehicle, netId
end

local function configuredSourceReach(entries, lease, lengthKey, fallback)
	if not lease or not lease.position then return fallback end

	for i = 1, #(entries or {}) do
		local entry = entries[i]
		local location = entry.location or entry
		local prop = entry.prop
		local model = type(prop) == 'string' and joaat(prop) or tonumber(prop)

		if location
			and (not model or model == lease.model)
			and distanceBetween(location, lease.position) <= 1.0
		then
			return math.max(tonumber(entry[lengthKey]) or fallback, 0.1)
		end
	end

	return fallback
end

local function getGasPumpReach(lease)
	local fallback = tonumber(nozzleSettings.maxDistance) or 7.5

	return configuredSourceReach(config.customGasPumpLocations, lease, 'ropeLength', fallback)
end

local function getChargerReach(lease)
	local fallback = tonumber(electricSettings.maxDistance) or 7.5

	return configuredSourceReach(electricSettings.chargerLocations, lease, 'cableLength', fallback)
end

local function validateVehicleAtSource(playerId, vehicle, pumpKey, pumpToken, maxDistance)
	if occupancySettings.enabled == false or not pumpKey then return false end

	clearExpiredPumpLeases()

	local lease = pumpLeases[pumpKey]

	if not lease
		or lease.owner ~= playerId
		or pumpToken and lease.token ~= pumpToken
		or not lease.position
	then return false end

	local tolerance = math.max(tonumber(validation.sourceVehicleTolerance) or 4.0, 0.0)

	return distanceBetween(GetEntityCoords(vehicle), lease.position) <= math.max(tonumber(maxDistance) or 0.0, 0.1) + tolerance
end

local function getFuelState(vehicle, fallback)
	local fuel = tonumber(Entity(vehicle).state.fuel)

	if fuel == nil then
		fuel = tonumber(fallback)

		if fuel == nil or fuel < 0 or fuel > 100 then return end

		Entity(vehicle).state:set('fuel', fuel, true)
	end

	return math.clamp(fuel, 0, 100)
end

local function getFuelPremiumRatio(vehicle)
	return fuelGrades.clampRatio(Entity(vehicle).state.fuelPremiumRatio)
end

exports('getFuelPremiumRatio', function(vehicle)
	if not vehicle or vehicle == 0 or GetEntityType(vehicle) ~= 2 then return end

	return getFuelPremiumRatio(vehicle)
end)

exports('setFuelPremiumRatio', function(vehicle, premiumRatio)
	if not vehicle or vehicle == 0 or GetEntityType(vehicle) ~= 2 then return false end

	Entity(vehicle).state:set('fuelPremiumRatio', fuelGrades.clampRatio(premiumRatio), true)

	return true
end)

local function getPetrolCan(playerId)
	local item = ox_inventory:GetCurrentWeapon(playerId)

	if not item or item.name ~= 'WEAPON_PETROLCAN' then return end

	local ammo = tonumber(item.metadata and (item.metadata.ammo or item.metadata.durability)) or 0
	local premiumRatio = fuelGrades.clampRatio(item.metadata and item.metadata.fuelPremiumRatio)

	return item, math.clamp(ammo, 0, 100), premiumRatio
end

local function portableCapacity()
	return math.max(tonumber(portableSettings.capacityKwh) or 12.0, 0.1)
end

local function portableItemName()
	return tostring(portableSettings.itemName or 'portable_ev_charger')
end

local function applyPortableMetadata(metadata, serial, chargeKwh, deployedToken)
	local capacity = portableCapacity()

	metadata = metadata or {}
	chargeKwh = math.clamp(tonumber(chargeKwh) or capacity, 0, capacity)
	metadata.portableSerial = serial or metadata.portableSerial
	metadata.portableChargeKwh = chargeKwh
	metadata.portableCapacityKwh = capacity
	metadata.portableChargePercent = math.floor((chargeKwh / capacity) * 100 + 0.5)
	metadata.portableCharge = ('%.2f / %.2f kWh'):format(chargeKwh, capacity)
	metadata.oxFuelDeployment = deployedToken or nil

	return metadata, chargeKwh, capacity
end

local function findPortableItem(playerId, serial, preferredSlot)
	local itemName = portableItemName()
	local preferred = tonumber(preferredSlot) and ox_inventory:GetSlot(playerId, tonumber(preferredSlot)) or nil

	if preferred and preferred.name == itemName then
		local preferredSerial = preferred.metadata and preferred.metadata.portableSerial

		if not serial or not preferredSerial or tostring(preferredSerial) == tostring(serial) then return preferred end
	end

	local items = ox_inventory:GetInventoryItems(playerId) or {}

	for _, item in pairs(items) do
		if item and item.name == itemName then
			local itemSerial = item.metadata and item.metadata.portableSerial

			if not serial or tostring(itemSerial or '') == tostring(serial) then return item end
		end
	end
end

local function writePortableMetadata(playerId, deployment, chargeKwh, deployedToken)
	local item = findPortableItem(playerId, deployment and deployment.serial, deployment and deployment.slot)

	if not item then return end

	local metadata
	local capacity

	metadata, chargeKwh, capacity = applyPortableMetadata(
		item.metadata,
		deployment and deployment.serial,
		chargeKwh,
		deployedToken
	)
	ox_inventory:SetMetadata(playerId, item.slot, metadata)

	if deployment then
		deployment.slot = item.slot
		deployment.chargeKwh = chargeKwh
	end

	return item, chargeKwh
end

local function releasePortableDeployment(playerId, token)
	local deployment = portableDeployments[playerId]

	if not deployment or token and deployment.token ~= token then return false end

	writePortableMetadata(playerId, deployment, deployment.chargeKwh, nil)
	portableDeployments[playerId] = nil

	return true
end

lib.callback.register('ox_fuel:deployPortableCharger', function(source, slot, payload)
	if electricSettings.enabled == false or portableSettings.enabled == false then return end
	if hasActiveSession(source) or portableDeployments[source] then
		notifyPlayer(source, locale('portable_already_deployed'))
		return
	end

	local position = positionFromPayload(payload)
	local playerPos = playerPosition(source)
	local maxDeployDistance = math.max(tonumber(portableSettings.deployDistance) or 1.05, 0.5) + 2.5

	if not position or not playerPos or distanceBetween(position, playerPos) > maxDeployDistance then return end

	local item = findPortableItem(source, nil, slot)

	if not item then
		notifyPlayer(source, locale('portable_item_missing'))
		return
	end

	portableSessionCounter = portableSessionCounter + 1

	local capacity = portableCapacity()
	local metadata = item.metadata or {}
	local chargeKwh = math.clamp(tonumber(metadata.portableChargeKwh) or capacity, 0, capacity)
	local serial = tostring(metadata.portableSerial or ('EVP-%s-%s-%s'):format(source, os.time(), portableSessionCounter))
	local token = ('%s:portable:%s'):format(source, portableSessionCounter)
	local deployment = {
		token = token,
		serial = serial,
		slot = item.slot,
		position = position,
		chargeKwh = chargeKwh,
	}

	portableDeployments[source] = deployment
	writePortableMetadata(source, deployment, chargeKwh, token)

	return {
		token = token,
		serial = serial,
		chargeKwh = chargeKwh,
		capacityKwh = capacity,
	}
end)

lib.callback.register('ox_fuel:pickupPortableCharger', function(source, token)
	local deployment = portableDeployments[source]

	if not deployment or deployment.token ~= token or hasActiveSession(source) then return false end

	local position = playerPosition(source)
	local maxDistance = math.max(tonumber(portableSettings.pickupDistance) or 3.0, 1.0)

	if not position or distanceBetween(position, deployment.position) > maxDistance then
		notifyPlayer(source, locale('portable_too_far'))
		return false
	end

	return releasePortableDeployment(source, token)
end)

RegisterNetEvent('ox_fuel:cancelPortableDeployment', function(token)
	releasePortableDeployment(source, token)
end)

if portableSettings.enabled ~= false then
	ox_inventory:registerHook('swapItems', function(payload)
		local item = type(payload.fromSlot) == 'table' and payload.fromSlot or nil
		local metadata = item and (item.metadata or {})
		local deployment = portableDeployments[payload.source]
		local deploymentItem = deployment and item and item.name == portableItemName() and (
			tonumber(item.slot) == tonumber(deployment.slot)
			or tostring(metadata.portableSerial or '') == tostring(deployment.serial)
			or tostring(metadata.oxFuelDeployment or '') == tostring(deployment.token)
		)

		if not deploymentItem then return end
		if tostring(payload.fromInventory) == tostring(payload.toInventory) then
			local toSlot = type(payload.toSlot) == 'table' and payload.toSlot.slot or tonumber(payload.toSlot)

			if toSlot then deployment.slot = toSlot end
			return
		end

		notifyPlayer(payload.source, locale('portable_deployed_locked'))
		return false
	end, {
		itemFilter = { [portableItemName()] = true },
	})
end

lib.callback.register('ox_fuel:getPurchaseOptions', function(source)
	local methods = getPaymentMethods(source)
	local defaultPayment = type(paymentSettings.defaultMethod) == 'string' and string.lower(paymentSettings.defaultMethod) or 'cash'
	local hasDefault = false

	for i = 1, #methods do
		if methods[i].id == defaultPayment then
			hasDefault = true
			break
		end
	end

	if #methods > 0 and not hasDefault then
		defaultPayment = methods[1].id
	end

	return {
		defaultGrade = fuelGrades.resolve().id,
		defaultPayment = defaultPayment,
		grades = fuelGrades.getAll(),
		payments = methods,
	}
end)

lib.callback.register('ox_fuel:getPortablePurchaseOptions', function(source)
	if electricSettings.enabled == false
		or portableSettings.enabled == false
		or portableSettings.purchaseEnabled == false
	then return end

	local methods = getPaymentMethods(source)
	local defaultPayment = type(paymentSettings.defaultMethod) == 'string' and string.lower(paymentSettings.defaultMethod) or 'cash'
	local hasDefault = false

	if #methods == 0 then return end

	for i = 1, #methods do
		if methods[i].id == defaultPayment then
			hasDefault = true
			break
		end
	end

	if not hasDefault then defaultPayment = methods[1].id end

	return {
		price = roundPrice(math.max(tonumber(portableSettings.purchasePrice) or 2500.0, 0)),
		capacityKwh = portableCapacity(),
		defaultPayment = defaultPayment,
		payments = methods,
	}
end)

lib.callback.register('ox_fuel:startFueling', function(source, netId, isPump, reportedFuel, reportedClass, gradeId, paymentId)
	if type(isPump) ~= 'boolean' then return end
	if hasActiveSession(source) then return end

	local vehicle, validatedNetId = validateFuelingVehicle(source, netId)

	if not vehicle then
		notifyPlayer(source, locale('vehicle_far'))
		return
	end

	if electricProfiles.isElectricModel(GetEntityModel(vehicle)) then
		notifyPlayer(source, locale('electric_requires_charger'))
		return
	end

	local sourceLease
	local sourceKey
	local sourceReach

	if isPump and nozzleSettings.attachToFuelCap ~= false then
		sourceLease, sourceKey = getPlayerActiveGasPumpLease(source)

		if sourceLease and sourceKey then
			sourceReach = getGasPumpReach(sourceLease)

			if not validateVehicleAtSource(source, vehicle, sourceKey, sourceLease.token, sourceReach) then
				notifyPlayer(source, locale('nozzle_too_far'))
				return
			end
		end
	end

	local vehicleClass = vehicleProfiles.normalizeClass(reportedClass)
	local vehicleType = type(GetVehicleType) == 'function' and GetVehicleType(vehicle) or nil

	if not vehicleClass or not vehicleProfiles.isClassCompatibleWithType(vehicleClass, vehicleType) then return end

	local profile = vehicleProfiles.resolve(GetEntityModel(vehicle), vehicleClass)
	local tankCapacityGallons = profile.tankCapacityGallons
	local fuel = getFuelState(vehicle, reportedFuel)
	local currentPremiumRatio = getFuelPremiumRatio(vehicle)
	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local gallonsPerSecond = math.max(tonumber(isPump and fuelingSettings.pumpGallonsPerSecond or fuelingSettings.canGallonsPerSecond) or 0, 0)
	local volumePerTick = gallonsPerSecond * (refillTick / 1000)

	if not fuel or tankCapacityGallons <= 0 or volumePerTick <= 0 then return end

	local maxVolume = tankCapacityGallons * ((100 - fuel) / 100)
	local petrolCanSlot
	local grade
	local payment
	local sourcePremiumRatio = 0
	local pricePerGallon = 0
	local availableFunds = 0

	if maxVolume <= 0.0001 then
		notifyPlayer(source, locale('tank_full'))
		return
	end

	if not isPump then
		local item, ammo, canPremiumRatio = getPetrolCan(source)
		local canCapacityGallons = tonumber(config.petrolCan and config.petrolCan.capacityGallons) or 5.3

		if not item or canCapacityGallons <= 0 then return end

		maxVolume = math.min(maxVolume, canCapacityGallons * (ammo / 100))
		petrolCanSlot = item.slot
		sourcePremiumRatio = canPremiumRatio
		grade = fuelGrades.describeRatio(canPremiumRatio)

		if maxVolume <= 0.0001 then
			notifyPlayer(source, locale('petrolcan_not_enough_fuel'))
			return
		end
	else
		local requestedGrade = type(gradeId) == 'string' and string.lower(gradeId) or nil
		grade = fuelGrades.resolve(requestedGrade)

		if requestedGrade and grade.id ~= requestedGrade then return end

		payment = resolvePayment(source, paymentId or paymentSettings.defaultMethod or 'cash')

		if not payment then return end

		pricePerGallon = grade.pricePerGallon
		availableFunds = payment.balance
		sourcePremiumRatio = grade.premiumRatio

		local firstTickPrice = roundPrice(math.min(volumePerTick, maxVolume) * pricePerGallon)

		if firstTickPrice > availableFunds then
			notifyPlayer(source, locale('not_enough_money', firstTickPrice - availableFunds))
			return
		end

		if pricePerGallon > 0 then
			maxVolume = math.min(maxVolume, availableFunds / pricePerGallon)
		end
	end

	local maxTicks = math.ceil(maxVolume / volumePerTick)
	local vintageQuirk = isPump and sourceLease and resolveVintagePumpQuirk(sourceLease.model, maxTicks) or nil

	if vintageQuirk and vintageQuirk.type == 'slow_flow' then
		volumePerTick = volumePerTick * vintageQuirk.flowMultiplier
		maxTicks = math.ceil(maxVolume / volumePerTick)
	elseif vintageQuirk and not vintageQuirk.triggerTick then
		vintageQuirk = nil
	end

	fuelingSessionCounter = fuelingSessionCounter + 1

	local startedAt = GetGameTimer()
	local graceMs = math.max(tonumber(validation.sessionGraceMs) or 10000, 0)
	local sessionId = ('%s:%s'):format(source, fuelingSessionCounter)
	local chaosSession = {}
	local engineChaos = resolveEngineChaos(source, vehicle, chaosSession)
	local engineOutcomeType = engineChaos and engineChaos.outcome and engineChaos.outcome.type
	local extraDuration = vintageQuirk and vintageQuirk.durationMs or 0
	local session = {
		id = sessionId,
		vehicle = vehicle,
		netId = validatedNetId,
		isPump = isPump,
		startFuel = fuel,
		maxTicks = maxTicks,
		maxVolume = maxVolume,
		tankCapacityGallons = tankCapacityGallons,
		volumePerTick = volumePerTick,
		pricePerGallon = pricePerGallon,
		paymentId = payment and payment.id or nil,
		sourcePremiumRatio = sourcePremiumRatio,
		startPremiumRatio = currentPremiumRatio,
		gradeLabel = grade.label,
		gradeShortLabel = grade.shortLabel,
		paymentLabel = payment and payment.label or nil,
		paymentShortLabel = payment and payment.shortLabel or nil,
		petrolCanSlot = petrolCanSlot,
		pumpKey = sourceKey,
		pumpToken = sourceLease and sourceLease.token or nil,
		sourceMaxDistance = sourceReach,
		startedAt = startedAt,
		expiresAt = startedAt + (maxTicks * refillTick) + graceMs + extraDuration,
		chaosMajor = chaosSession.chaosMajor == true,
		chaosAbort = engineOutcomeType == 'fire' or engineOutcomeType == 'explosion',
		chaosVintageQuirk = vintageQuirk,
	}

	fuelingSessions[source] = session

	return {
		id = sessionId,
		fuel = fuel,
		maxTicks = maxTicks,
		maxVolume = maxVolume,
		tankCapacityGallons = tankCapacityGallons,
		volumePerTick = volumePerTick,
		pricePerGallon = pricePerGallon,
		availableFunds = availableFunds,
		gradeId = grade.id,
		gradeLabel = grade.label,
		gradeShortLabel = grade.shortLabel,
		paymentId = payment and payment.id or nil,
		paymentLabel = payment and payment.label or nil,
		paymentShortLabel = payment and payment.shortLabel or nil,
		chaosEngine = engineChaos,
		chaosVintageQuirk = vintageQuirk,
	}
end)

lib.callback.register('ox_fuel:chaosDriveOff', function(source, netId, customPumpIndex)
	local feature = getChaosFeature('driveOff')
	local session = fuelingSessions[source]

	if not feature or not session or not session.isPump or not session.pumpKey then return end

	local vehicle = validateFuelingVehicle(source, netId, session.vehicle, true)
	local lease = pumpLeases[session.pumpKey]

	if not vehicle or not lease or lease.owner ~= source or lease.token ~= session.pumpToken then return end

	local configuredReach = math.max(tonumber(session.sourceMaxDistance) or tonumber(nozzleSettings.maxDistance) or 7.5, 0.5)
	local minimumBreakDistance = math.max(configuredReach - 1.0, 0.5)

	if distanceBetween(GetEntityCoords(vehicle), lease.position) < minimumBreakDistance then return end

	local now = GetGameTimer()
	local graceMs = math.max(tonumber(validation.sessionGraceMs) or 10000, 0)
	local outcome = { type = 'hose_break' }
	session.chaosDriveOff = true
	session.chaosDriveOffAt = now
	session.chaosDriveOffMaxTicks = math.max(math.floor((now - session.startedAt) / math.max(tonumber(config.refillTick) or 0, 1)) + 1, 0)
	session.expiresAt = math.max(session.expiresAt, now + graceMs)

	if not canTriggerMajorChaos(source, session) then return outcome end

	if rollChaos(feature.explosionChance) then
		outcome = {
			type = 'explosion',
			explosionType = math.floor(tonumber(feature.explosionType) or 6),
			damageScale = math.max(tonumber(feature.damageScale) or 0.55, 0),
			cameraShake = math.max(tonumber(feature.cameraShake) or 0.45, 0),
		}
		markMajorChaos(source, session, 'hose drive-off explosion')
	elseif rollChaos(feature.fireChance) then
		outcome = {
			type = 'fire',
			engineDamage = math.max(tonumber(feature.engineDamage) or 180.0, 0),
			bodyDamage = math.max(tonumber(feature.bodyDamage) or 120.0, 0),
			fireDurationMs = math.max(math.floor(tonumber(feature.fireDurationMs) or 6000), 500),
		}
		markMajorChaos(source, session, 'hose drive-off fire')
	else
		customPumpIndex = tonumber(customPumpIndex)
		local _, location, model, damageable = getCustomPumpEntry(customPumpIndex)
		local customPumpKey = location and model and getPumpKey(model, location) or nil

		if damageable
			and customPumpKey == session.pumpKey
			and not destroyedCustomPumps[customPumpIndex]
			and customPumpPropSettings.synchronizeExplosions ~= false
			and rollChaos(feature.pumpDamageChance)
		then
			outcome = { type = 'pump_destroyed', pumpDestroyed = true }
			markMajorChaos(source, session, 'hose drive-off pump destruction')
			markCustomPumpDestroyed(customPumpIndex, 0)
		elseif rollChaos(feature.vehicleDamageChance) then
			outcome = {
				type = 'vehicle_damage',
				engineDamage = math.max(tonumber(feature.engineDamage) or 180.0, 0),
				bodyDamage = math.max(tonumber(feature.bodyDamage) or 120.0, 0),
			}
			markMajorChaos(source, session, 'hose drive-off vehicle damage')
		end
	end

	return outcome
end)

lib.callback.register('ox_fuel:finishFueling', function(source, sessionId, requestedTicks)
	local session = fuelingSessions[source]

	if not session or session.id ~= sessionId then return end

	fuelingSessions[source] = nil

	local now = GetGameTimer()

	if now > session.expiresAt then return end

	local vehicle = validateFuelingVehicle(source, session.netId, session.vehicle, session.pumpKey ~= nil)

	if not vehicle then
		notifyPlayer(source, locale('vehicle_far'))
		return
	end

	if session.pumpKey and not session.chaosDriveOff and not validateVehicleAtSource(
		source,
		vehicle,
		session.pumpKey,
		session.pumpToken,
		session.sourceMaxDistance
	) then
		notifyPlayer(source, locale('pump_lease_lost'))
		return
	end

	requestedTicks = math.max(math.floor(tonumber(requestedTicks) or 0), 0)

	if session.chaosAbort then
		requestedTicks = 0
	elseif session.chaosDriveOffMaxTicks then
		requestedTicks = math.min(requestedTicks, session.chaosDriveOffMaxTicks)
	end

	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local tickTolerance = math.max(math.floor(tonumber(validation.tickTolerance) or 2), 0)
	local elapsedTicks = math.floor((now - session.startedAt) / refillTick) + 1 + tickTolerance
	local currentFuel = getFuelState(vehicle, session.startFuel)

	if not currentFuel then return end

	local completedTicks = math.min(requestedTicks, elapsedTicks, session.maxTicks)

	if completedTicks <= 0 then return end

	local availableVolume = session.tankCapacityGallons * ((100 - currentFuel) / 100)
	local transferredVolume = math.min(completedTicks * session.volumePerTick, session.maxVolume, availableVolume)

	if transferredVolume <= 0.0001 then return end

	if session.isPump then
		local price = roundPrice(transferredVolume * session.pricePerGallon)
		local fuel = math.min(currentFuel + ((transferredVolume / session.tankCapacityGallons) * 100), 100.0)
		local currentVolume = session.tankCapacityGallons * (currentFuel / 100)
		local premiumRatio = fuelGrades.blend(
			currentVolume,
			getFuelPremiumRatio(vehicle),
			transferredVolume,
			session.sourcePremiumRatio
		)

		if price > 0 and not chargePayment(source, price, session.paymentId) then
			local balance = getPaymentBalance(source, session.paymentId) or 0
			notifyPlayer(source, locale('not_enough_money', math.max(price - balance, 0)))
			return
		end

		if not setFuelState(session.netId, fuel, premiumRatio) then return end

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('fuel_success', math.floor(fuel), price)
		})

		return {
			fuel = fuel,
			price = price,
			ticks = completedTicks,
			volume = transferredVolume,
			premiumRatio = premiumRatio,
			gradeLabel = session.gradeLabel,
			gradeShortLabel = session.gradeShortLabel,
			paymentLabel = session.paymentLabel,
			paymentShortLabel = session.paymentShortLabel,
		}
	end

	local item, ammo, canPremiumRatio = getPetrolCan(source)
	local canCapacityGallons = tonumber(config.petrolCan and config.petrolCan.capacityGallons) or 5.3

	if not item or item.slot ~= session.petrolCanSlot or canCapacityGallons <= 0 then return end

	transferredVolume = math.min(transferredVolume, canCapacityGallons * (ammo / 100))

	if transferredVolume <= 0.0001 then return end

	local durabilityUsed = (transferredVolume / canCapacityGallons) * 100
	local durability = math.max(math.floor(ammo - durabilityUsed + 0.5), 0)
	local fuel = math.min(currentFuel + ((transferredVolume / session.tankCapacityGallons) * 100), 100.0)
	local currentVolume = session.tankCapacityGallons * (currentFuel / 100)
	local premiumRatio = fuelGrades.blend(
		currentVolume,
		getFuelPremiumRatio(vehicle),
		transferredVolume,
		canPremiumRatio
	)
	item.metadata = item.metadata or {}
	item.metadata.durability = durability
	item.metadata.ammo = durability

	if durability <= 0 then
		item.metadata.fuelPremiumRatio = 0
		item.metadata.fuelGrade = fuelGrades.resolve().id
	end

	ox_inventory:SetMetadata(source, item.slot, item.metadata)
	setFuelState(session.netId, fuel, premiumRatio)

	return {
		fuel = fuel,
		durability = durability,
		ticks = completedTicks,
		volume = transferredVolume,
		premiumRatio = premiumRatio,
		gradeLabel = session.gradeLabel,
		gradeShortLabel = session.gradeShortLabel,
	}
end)

RegisterNetEvent('ox_fuel:cancelFueling', function(sessionId)
	local session = fuelingSessions[source]

	if session and session.id == sessionId then
		fuelingSessions[source] = nil
	end
end)

local function getChargingMode(modeId)
	modeId = type(modeId) == 'string' and string.lower(modeId) or nil

	local mode = modeId and electricSettings.modes and electricSettings.modes[modeId] or nil

	if type(mode) ~= 'table' then return end

	local pricePerKwh = math.max(tonumber(mode.pricePerKwh) or 0, 0)
	local kwhPerSecond = math.max(tonumber(mode.kwhPerSecond) or 0, 0)

	if kwhPerSecond <= 0 then return end

	return {
		id = modeId,
		label = tostring(mode.label or modeId),
		shortLabel = tostring(mode.shortLabel or mode.label or modeId):upper(),
		pricePerKwh = pricePerKwh,
		kwhPerSecond = kwhPerSecond,
		displayPowerKw = math.max(tonumber(mode.displayPowerKw) or 0, 0),
	}
end

local function getChargingModes()
	local output = {}
	local seen = {}
	local order = electricSettings.modeOrder or {}
	local modes = electricSettings.modes or {}

	local function append(id)
		if seen[id] then return end

		local mode = getChargingMode(id)

		if mode then
			seen[id] = true
			output[#output + 1] = mode
		end
	end

	for i = 1, #order do
		if type(order[i]) == 'string' then append(string.lower(order[i])) end
	end

	for id in pairs(modes) do
		if type(id) == 'string' then append(string.lower(id)) end
	end

	return output
end

lib.callback.register('ox_fuel:getChargingOptions', function(source)
	if electricSettings.enabled == false then return end

	local methods = getPaymentMethods(source)
	local modes = getChargingModes()
	local defaultMode = type(electricSettings.defaultMode) == 'string' and string.lower(electricSettings.defaultMode) or 'standard'
	local defaultPayment = type(paymentSettings.defaultMethod) == 'string' and string.lower(paymentSettings.defaultMethod) or 'cash'

	if not getChargingMode(defaultMode) and modes[1] then defaultMode = modes[1].id end

	local hasDefaultPayment = false

	for i = 1, #methods do
		if methods[i].id == defaultPayment then
			hasDefaultPayment = true
			break
		end
	end

	if #methods > 0 and not hasDefaultPayment then defaultPayment = methods[1].id end

	return {
		defaultMode = defaultMode,
		defaultPayment = defaultPayment,
		modes = modes,
		payments = methods,
	}
end)

lib.callback.register('ox_fuel:startCharging', function(source, netId, reportedFuel, modeId, paymentId)
	if electricSettings.enabled == false then return end
	if hasActiveSession(source) then return end

	local vehicle, validatedNetId = validateFuelingVehicle(source, netId)

	if not vehicle then
		notifyPlayer(source, locale('vehicle_far'))
		return
	end

	local model = GetEntityModel(vehicle)
	local profile = electricProfiles.resolve(model)

	if not profile then
		notifyPlayer(source, locale('charge_electric_only'))
		return
	end

	local chargerLease, chargerKey = getPlayerActivePumpLease(source, electricSettings.chargerModel)
	local chargerDistance = (tonumber(electricSettings.maxDistance) or 7.5) + 1.0
	local chargingPlayerPosition = playerPosition(source)
	local chargerIndex = chargerLease and getChargerLocationIndex(chargerLease.position)

	if chargerIndex and destroyedChargers[chargerIndex] then
		notifyPlayer(source, locale('charger_destroyed'))
		return
	end

	if not chargerLease or not chargingPlayerPosition or distanceBetween(chargingPlayerPosition, chargerLease.position) > chargerDistance then
		notifyPlayer(source, locale('pump_lease_lost'))
		return
	end

	local sourceReach = chargerKey and getChargerReach(chargerLease) or nil

	if chargerKey and not validateVehicleAtSource(source, vehicle, chargerKey, chargerLease.token, sourceReach) then
		notifyPlayer(source, locale('charge_cable_too_far'))
		return
	end

	local mode = getChargingMode(modeId or electricSettings.defaultMode)
	local payment = resolvePayment(source, paymentId or paymentSettings.defaultMethod or 'cash')
	local fuel = getFuelState(vehicle, reportedFuel)
	local batteryCapacityKwh = math.max(tonumber(profile.batteryCapacityKwh) or 0, 0)
	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local energyPerTick = mode and mode.kwhPerSecond * (refillTick / 1000) or 0

	if not mode or not payment or not fuel or batteryCapacityKwh <= 0 or energyPerTick <= 0 then return end

	local maxEnergy = batteryCapacityKwh * ((100 - fuel) / 100)

	if maxEnergy <= 0.0001 then
		notifyPlayer(source, locale('battery_full'))
		return
	end

	local firstTickPrice = roundPrice(math.min(energyPerTick, maxEnergy) * mode.pricePerKwh)

	if firstTickPrice > payment.balance then
		notifyPlayer(source, locale('not_enough_money', firstTickPrice - payment.balance))
		return
	end

	if mode.pricePerKwh > 0 then
		maxEnergy = math.min(maxEnergy, payment.balance / mode.pricePerKwh)
	end

	local maxTicks = math.ceil(maxEnergy / energyPerTick)

	if maxTicks <= 0 then return end

	chargingSessionCounter = chargingSessionCounter + 1

	local startedAt = GetGameTimer()
	local graceMs = math.max(tonumber(validation.sessionGraceMs) or 10000, 0)
	local sessionId = ('%s:charge:%s'):format(source, chargingSessionCounter)

	local session = {
		id = sessionId,
		vehicle = vehicle,
		netId = validatedNetId,
		startFuel = fuel,
		batteryCapacityKwh = batteryCapacityKwh,
		energyPerTick = energyPerTick,
		maxEnergy = maxEnergy,
		maxTicks = maxTicks,
		pricePerKwh = mode.pricePerKwh,
		displayPowerKw = mode.displayPowerKw,
		paymentId = payment.id,
		modeLabel = mode.label,
		modeShortLabel = mode.shortLabel,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		pumpKey = chargerKey,
		pumpToken = chargerLease.token,
		sourceMaxDistance = sourceReach,
		startedAt = startedAt,
		expiresAt = startedAt + (maxTicks * refillTick) + graceMs,
	}
	local rapidFeature = getChaosFeature('rapidChargeFault')
	local enabledModes = rapidFeature and rapidFeature.modes

	if rapidFeature and (type(enabledModes) ~= 'table' or enabledModes[mode.id] == true) then
		session.chaosFault = resolveChargingFault(source, session, 'rapidChargeFault', 'rapid_shutdown')
	end

	chargingSessions[source] = session

	return {
		id = sessionId,
		fuel = fuel,
		batteryCapacityKwh = batteryCapacityKwh,
		energyPerTick = energyPerTick,
		maxEnergy = maxEnergy,
		maxTicks = maxTicks,
		pricePerKwh = mode.pricePerKwh,
		displayPowerKw = mode.displayPowerKw,
		availableFunds = payment.balance,
		modeId = mode.id,
		modeLabel = mode.label,
		modeShortLabel = mode.shortLabel,
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		chaosFault = session.chaosFault,
	}
end)

lib.callback.register('ox_fuel:finishCharging', function(source, sessionId, requestedTicks)
	local session = chargingSessions[source]

	if not session or session.id ~= sessionId then return end

	chargingSessions[source] = nil

	local now = GetGameTimer()

	if now > session.expiresAt then return end

	local vehicle = validateFuelingVehicle(source, session.netId, session.vehicle, session.pumpKey ~= nil)

	if not vehicle or not electricProfiles.isElectricModel(GetEntityModel(vehicle)) then
		notifyPlayer(source, locale('vehicle_far'))
		return
	end

	if session.pumpKey then
		if not validateVehicleAtSource(
			source,
			vehicle,
			session.pumpKey,
			session.pumpToken,
			session.sourceMaxDistance
		) then
			notifyPlayer(source, locale('pump_lease_lost'))
			return
		end
	else
		local chargerLease = getPlayerActivePumpLease(source, electricSettings.chargerModel)
		local chargingPlayerPosition = playerPosition(source)
		local chargerDistance = (tonumber(electricSettings.maxDistance) or 7.5) + 1.0

		if not chargerLease or not chargingPlayerPosition or distanceBetween(chargingPlayerPosition, chargerLease.position) > chargerDistance then
			notifyPlayer(source, locale('pump_lease_lost'))
			return
		end
	end

	requestedTicks = math.max(math.floor(tonumber(requestedTicks) or 0), 0)

	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local tickTolerance = math.max(math.floor(tonumber(validation.tickTolerance) or 2), 0)
	local elapsedTicks = math.floor((now - session.startedAt) / refillTick) + 1 + tickTolerance
	local completedTicks = math.min(requestedTicks, elapsedTicks, session.maxTicks)
	local chaosInterrupted = session.chaosFault
		and completedTicks >= (tonumber(session.chaosFault.faultTick) or math.huge)

	if chaosInterrupted then completedTicks = math.min(completedTicks, session.chaosFault.faultTick) end

	if completedTicks <= 0 then return end

	local currentFuel = getFuelState(vehicle, session.startFuel)

	if not currentFuel then return end

	local availableEnergy = session.batteryCapacityKwh * ((100 - currentFuel) / 100)
	local transferredEnergy = math.min(completedTicks * session.energyPerTick, session.maxEnergy, availableEnergy)

	if transferredEnergy <= 0.0001 then return end

	local price = roundPrice(transferredEnergy * session.pricePerKwh)
	local fuel = math.min(currentFuel + ((transferredEnergy / session.batteryCapacityKwh) * 100), 100.0)

	if price > 0 and not chargePayment(source, price, session.paymentId) then
		local balance = getPaymentBalance(source, session.paymentId) or 0
		notifyPlayer(source, locale('not_enough_money', math.max(price - balance, 0)))
		return
	end

	if not setFuelState(session.netId, fuel, 0) then return end

	if not chaosInterrupted then
		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('charging_success', math.floor(fuel), price),
		})
	end

	return {
		fuel = fuel,
		price = price,
		ticks = completedTicks,
		energy = transferredEnergy,
		modeLabel = session.modeLabel,
		modeShortLabel = session.modeShortLabel,
		paymentLabel = session.paymentLabel,
		paymentShortLabel = session.paymentShortLabel,
		chaosInterrupted = chaosInterrupted == true,
	}
end)

RegisterNetEvent('ox_fuel:cancelCharging', function(sessionId)
	local session = chargingSessions[source]

	if session and session.id == sessionId then
		chargingSessions[source] = nil
	end
end)

local function getPortableDeployment(playerId, token)
	local deployment = portableDeployments[playerId]

	if not deployment or deployment.token ~= token then return end

	local item = findPortableItem(playerId, deployment.serial, deployment.slot)

	if not item then return end

	local metadata = item.metadata or {}
	local deployedToken = metadata.oxFuelDeployment

	if deployedToken and tostring(deployedToken) ~= tostring(deployment.token) then return end

	local capacity = portableCapacity()
	local chargeKwh = math.clamp(tonumber(metadata.portableChargeKwh) or deployment.chargeKwh or capacity, 0, capacity)
	deployment.slot = item.slot
	deployment.chargeKwh = chargeKwh

	if not deployedToken or tostring(metadata.portableSerial or '') ~= tostring(deployment.serial) then
		writePortableMetadata(playerId, deployment, chargeKwh, deployment.token)
	end

	return deployment, item, chargeKwh, capacity
end

lib.callback.register('ox_fuel:damagePortableCharger', function(source, token)
	local deployment = getPortableDeployment(source, token)

	if not deployment then return end

	local position = playerPosition(source)
	local damageSettings = portableSettings.damageEffects or {}
	local maxDistance = math.max(tonumber(damageSettings.reportDistance) or 20.0, 3.0)

	if not position or distanceBetween(position, deployment.position) > maxDistance then return end

	local rechargeSession = portableRechargeSessions[source]

	if rechargeSession and rechargeSession.pumpKey then
		releasePumpLease(rechargeSession.pumpKey, source, rechargeSession.pumpToken)
	end

	portableChargingSessions[source] = nil
	portableRechargeSessions[source] = nil
	writePortableMetadata(source, deployment, 0, deployment.token)

	return {
		chargeKwh = 0,
		capacityKwh = portableCapacity(),
	}
end)

lib.callback.register('ox_fuel:startPortableCharging', function(source, token, netId, reportedFuel)
	if electricSettings.enabled == false or portableSettings.enabled == false or hasActiveSession(source) then return end

	local deployment, _, packCharge, packCapacity = getPortableDeployment(source, token)
	local vehicle, validatedNetId = validateFuelingVehicle(source, netId)

	if not deployment or not vehicle then
		notifyPlayer(source, locale(not deployment and 'portable_item_missing' or 'vehicle_far'))
		return
	end

	local profile = electricProfiles.resolve(GetEntityModel(vehicle))

	if not profile then
		notifyPlayer(source, locale('charge_electric_only'))
		return
	end

	local cableReach = math.max(tonumber(portableSettings.cableMaxLength) or 5.0, 0.5)
	local sourceTolerance = math.max(tonumber(validation.sourceVehicleTolerance) or 4.0, 0.0)

	if distanceBetween(GetEntityCoords(vehicle), deployment.position) > cableReach + sourceTolerance then
		notifyPlayer(source, locale('charge_cable_too_far'))
		return
	end

	if packCharge <= 0.0001 then
		notifyPlayer(source, locale('portable_empty'))
		return
	end

	local fuel = getFuelState(vehicle, reportedFuel)
	local batteryCapacityKwh = math.max(tonumber(profile.batteryCapacityKwh) or 0, 0)
	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local energyPerTick = math.max(tonumber(portableSettings.outputKwhPerSecond) or 0.20, 0) * (refillTick / 1000)

	if not fuel or batteryCapacityKwh <= 0 or energyPerTick <= 0 then return end

	local maxEnergy = math.min(batteryCapacityKwh * ((100 - fuel) / 100), packCharge)

	if maxEnergy <= 0.0001 then
		notifyPlayer(source, locale('battery_full'))
		return
	end

	local maxTicks = math.ceil(maxEnergy / energyPerTick)
	local startedAt = GetGameTimer()
	local graceMs = math.max(tonumber(validation.sessionGraceMs) or 10000, 0)
	portableSessionCounter = portableSessionCounter + 1

	local sessionId = ('%s:portable-charge:%s'):format(source, portableSessionCounter)

	local session = {
		id = sessionId,
		deploymentToken = token,
		vehicle = vehicle,
		netId = validatedNetId,
		startFuel = fuel,
		batteryCapacityKwh = batteryCapacityKwh,
		energyPerTick = energyPerTick,
		maxEnergy = maxEnergy,
		maxTicks = maxTicks,
		startedAt = startedAt,
		expiresAt = startedAt + (maxTicks * refillTick) + graceMs,
	}

	session.chaosFault = resolveChargingFault(source, session, 'portableThermalShutdown', 'portable_thermal')
	portableChargingSessions[source] = session

	return {
		id = sessionId,
		fuel = fuel,
		batteryCapacityKwh = batteryCapacityKwh,
		energyPerTick = energyPerTick,
		maxEnergy = maxEnergy,
		maxTicks = maxTicks,
		pricePerKwh = 0,
		displayPowerKw = math.max(tonumber(portableSettings.displayPowerKw) or 7.2, 0),
		availableFunds = 999999999,
		modeId = 'portable',
		modeLabel = locale('portable_mode'),
		modeShortLabel = locale('portable_mode_short'),
		paymentId = 'pack',
		paymentLabel = locale('portable_pack'),
		paymentShortLabel = locale('portable_pack_short'),
		packChargeKwh = packCharge,
		packCapacityKwh = packCapacity,
		chaosFault = session.chaosFault,
	}
end)

lib.callback.register('ox_fuel:finishPortableCharging', function(source, sessionId, requestedTicks)
	local session = portableChargingSessions[source]

	if not session or session.id ~= sessionId then return end
	portableChargingSessions[source] = nil

	local now = GetGameTimer()

	if now > session.expiresAt then return end

	local deployment, _, packCharge, packCapacity = getPortableDeployment(source, session.deploymentToken)
	local vehicle = validateFuelingVehicle(source, session.netId, session.vehicle, true)

	if not deployment or not vehicle or not electricProfiles.isElectricModel(GetEntityModel(vehicle)) then return end

	local cableReach = math.max(tonumber(portableSettings.cableMaxLength) or 5.0, 0.5)
	local sourceTolerance = math.max(tonumber(validation.sourceVehicleTolerance) or 4.0, 0.0)

	if distanceBetween(GetEntityCoords(vehicle), deployment.position) > cableReach + sourceTolerance then
		notifyPlayer(source, locale('charge_cable_too_far'))
		return
	end

	requestedTicks = math.max(math.floor(tonumber(requestedTicks) or 0), 0)

	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local tickTolerance = math.max(math.floor(tonumber(validation.tickTolerance) or 2), 0)
	local elapsedTicks = math.floor((now - session.startedAt) / refillTick) + 1 + tickTolerance
	local completedTicks = math.min(requestedTicks, elapsedTicks, session.maxTicks)
	local chaosInterrupted = session.chaosFault
		and completedTicks >= (tonumber(session.chaosFault.faultTick) or math.huge)

	if chaosInterrupted then completedTicks = math.min(completedTicks, session.chaosFault.faultTick) end

	if completedTicks <= 0 then return end

	local currentFuel = getFuelState(vehicle, session.startFuel)
	local vehicleSpace = currentFuel and session.batteryCapacityKwh * ((100 - currentFuel) / 100) or 0
	local transferredEnergy = math.min(completedTicks * session.energyPerTick, session.maxEnergy, vehicleSpace, packCharge)

	if transferredEnergy <= 0.0001 then return end

	local fuel = math.min(currentFuel + ((transferredEnergy / session.batteryCapacityKwh) * 100), 100.0)
	local remainingCharge = math.max(packCharge - transferredEnergy, 0)

	writePortableMetadata(source, deployment, remainingCharge, deployment.token)

	if not setFuelState(session.netId, fuel, 0) then
		writePortableMetadata(source, deployment, packCharge, deployment.token)
		return
	end

	if not chaosInterrupted then
		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('portable_charging_success', math.floor(fuel), remainingCharge),
		})
	end

	return {
		fuel = fuel,
		price = 0,
		ticks = completedTicks,
		energy = transferredEnergy,
		packChargeKwh = remainingCharge,
		packCapacityKwh = packCapacity,
		chaosInterrupted = chaosInterrupted == true,
	}
end)

RegisterNetEvent('ox_fuel:cancelPortableCharging', function(sessionId)
	local session = portableChargingSessions[source]

	if session and session.id == sessionId then portableChargingSessions[source] = nil end
end)

lib.callback.register('ox_fuel:startPortableRecharge', function(source, token, chargerModel, chargerPayload, modeId, paymentId)
	if electricSettings.enabled == false or portableSettings.enabled == false or hasActiveSession(source) then return end

	local deployment, _, packCharge, packCapacity = getPortableDeployment(source, token)
	local chargerLease
	local chargerKey
	local chargerPosition

	if occupancySettings.enabled == false then
		chargerPosition = positionFromPayload(chargerPayload)

		if tonumber(chargerModel) ~= tonumber(electricSettings.chargerModel)
			or not chargerPosition
			or not getChargerLocationIndex(chargerPosition)
		then return end
	else
		chargerLease, chargerKey = getPlayerActivePumpLease(source, electricSettings.chargerModel)
		chargerPosition = chargerLease and chargerLease.position or nil
	end

	local mode = getChargingMode(modeId or electricSettings.defaultMode)
	local payment = resolvePayment(source, paymentId or paymentSettings.defaultMethod or 'cash')

	if not deployment or not chargerPosition or not mode or not payment then return end

	local rechargeDistance = math.max(tonumber(portableSettings.rechargeDistance) or 3.0, 1.0)
	local sourceTolerance = math.max(tonumber(validation.sourceVehicleTolerance) or 4.0, 0.0)
	local playerPos = playerPosition(source)

	if not playerPos
		or distanceBetween(playerPos, chargerPosition) > rechargeDistance + 2.0
		or distanceBetween(deployment.position, chargerPosition) > rechargeDistance + sourceTolerance
	then
		notifyPlayer(source, locale('portable_recharge_too_far'))
		return
	end

	local maxEnergy = packCapacity - packCharge

	if maxEnergy <= 0.0001 then
		notifyPlayer(source, locale('portable_full'))
		return
	end

	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local energyPerTick = mode.kwhPerSecond * (refillTick / 1000)
	local firstTickPrice = roundPrice(math.min(energyPerTick, maxEnergy) * mode.pricePerKwh)

	if firstTickPrice > payment.balance then
		notifyPlayer(source, locale('not_enough_money', firstTickPrice - payment.balance))
		return
	end

	if mode.pricePerKwh > 0 then maxEnergy = math.min(maxEnergy, payment.balance / mode.pricePerKwh) end

	local maxTicks = math.ceil(maxEnergy / energyPerTick)
	local startedAt = GetGameTimer()
	local graceMs = math.max(tonumber(validation.sessionGraceMs) or 10000, 0)
	portableSessionCounter = portableSessionCounter + 1

	local sessionId = ('%s:portable-refill:%s'):format(source, portableSessionCounter)

	portableRechargeSessions[source] = {
		id = sessionId,
		deploymentToken = token,
		energyPerTick = energyPerTick,
		maxEnergy = maxEnergy,
		maxTicks = maxTicks,
		pricePerKwh = mode.pricePerKwh,
		displayPowerKw = mode.displayPowerKw,
		paymentId = payment.id,
		modeLabel = mode.label,
		modeShortLabel = mode.shortLabel,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		pumpKey = chargerKey,
		pumpToken = chargerLease and chargerLease.token or nil,
		sourcePosition = chargerPosition,
		startedAt = startedAt,
		expiresAt = startedAt + (maxTicks * refillTick) + graceMs,
	}

	return {
		id = sessionId,
		packChargeKwh = packCharge,
		packCapacityKwh = packCapacity,
		energyPerTick = energyPerTick,
		maxEnergy = maxEnergy,
		maxTicks = maxTicks,
		pricePerKwh = mode.pricePerKwh,
		displayPowerKw = mode.displayPowerKw,
		availableFunds = payment.balance,
		modeId = mode.id,
		modeLabel = mode.label,
		modeShortLabel = mode.shortLabel,
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
	}
end)

lib.callback.register('ox_fuel:finishPortableRecharge', function(source, sessionId, requestedTicks)
	local session = portableRechargeSessions[source]

	if not session or session.id ~= sessionId then return end
	portableRechargeSessions[source] = nil

	local now = GetGameTimer()
	local deployment, _, packCharge, packCapacity = getPortableDeployment(source, session.deploymentToken)

	if now > session.expiresAt or not deployment then return end

	local rechargeDistance = math.max(tonumber(portableSettings.rechargeDistance) or 3.0, 1.0)
	local sourceTolerance = math.max(tonumber(validation.sourceVehicleTolerance) or 4.0, 0.0)

	if occupancySettings.enabled == false then
		if distanceBetween(deployment.position, session.sourcePosition) > rechargeDistance + sourceTolerance then
			notifyPlayer(source, locale('portable_recharge_too_far'))
			return
		end
	else
		local lease = pumpLeases[session.pumpKey]

		if not lease
			or lease.owner ~= source
			or lease.token ~= session.pumpToken
			or now > lease.expiresAt
			or distanceBetween(deployment.position, lease.position) > rechargeDistance + sourceTolerance
		then
			notifyPlayer(source, locale('pump_lease_lost'))
			return
		end
	end

	requestedTicks = math.max(math.floor(tonumber(requestedTicks) or 0), 0)

	local refillTick = math.max(tonumber(config.refillTick) or 0, 1)
	local tickTolerance = math.max(math.floor(tonumber(validation.tickTolerance) or 2), 0)
	local elapsedTicks = math.floor((now - session.startedAt) / refillTick) + 1 + tickTolerance
	local completedTicks = math.min(requestedTicks, elapsedTicks, session.maxTicks)
	local availableSpace = packCapacity - packCharge
	local transferredEnergy = math.min(completedTicks * session.energyPerTick, session.maxEnergy, availableSpace)

	if transferredEnergy <= 0.0001 then return end

	local price = roundPrice(transferredEnergy * session.pricePerKwh)

	if price > 0 and not chargePayment(source, price, session.paymentId) then
		local balance = getPaymentBalance(source, session.paymentId) or 0
		notifyPlayer(source, locale('not_enough_money', math.max(price - balance, 0)))
		return
	end

	local chargeKwh = math.min(packCharge + transferredEnergy, packCapacity)
	writePortableMetadata(source, deployment, chargeKwh, deployment.token)

	TriggerClientEvent('ox_lib:notify', source, {
		type = 'success',
		description = locale('portable_recharge_success', math.floor((chargeKwh / packCapacity) * 100 + 0.5), price),
	})

	return {
		chargeKwh = chargeKwh,
		capacityKwh = packCapacity,
		price = price,
		energy = transferredEnergy,
		ticks = completedTicks,
	}
end)

RegisterNetEvent('ox_fuel:cancelPortableRecharge', function(sessionId)
	local session = portableRechargeSessions[source]

	if session and session.id == sessionId then portableRechargeSessions[source] = nil end
end)

local fuelCanSessionCounter = 0

local function validateFuelCanPump(playerId, model, payload)
	if model == nil and payload == nil then return true end

	local position = positionFromPayload(payload)
	local playerPos = playerPosition(playerId)
	local maxDistance = tonumber(occupancySettings.maxAcquireDistance) or 4.0
	local key = position and getPumpKey(model, position) or nil

	if not key or not playerPos or distanceBetween(playerPos, position) > maxDistance then return end

	local lease = pumpLeases[key]

	if lease and lease.owner ~= playerId and GetGameTimer() <= lease.expiresAt then return end

	return key
end

local function clearPortablePurchaseSession(playerId, sessionId)
	local session = portablePurchaseSessions[playerId]

	if not session or sessionId and session.id ~= sessionId then return end

	portablePurchaseSessions[playerId] = nil

	if session.pumpKey then
		releasePumpLease(session.pumpKey, playerId, session.pumpToken)
	end

	return session
end

lib.callback.register('ox_fuel:preparePortablePurchase', function(source, paymentId, chargerModel, chargerPayload)
	if electricSettings.enabled == false
		or portableSettings.enabled == false
		or portableSettings.purchaseEnabled == false
		or hasActiveSession(source)
	then return end

	local pumpKey = validateFuelCanPump(source, chargerModel, chargerPayload)

	if not pumpKey or tonumber(chargerModel) ~= tonumber(electricSettings.chargerModel) then return end
	if not ox_inventory:CanCarryItem(source, portableItemName(), 1) then
		notifyPlayer(source, locale('portable_cannot_carry'))
		return
	end

	local payment = resolvePayment(source, paymentId or paymentSettings.defaultMethod or 'cash')

	if not payment then return end

	local price = roundPrice(math.max(tonumber(portableSettings.purchasePrice) or 2500.0, 0))

	if price > payment.balance then
		notifyPlayer(source, locale('not_enough_money', price - payment.balance))
		return
	end

	local duration = math.max(math.floor(tonumber(portableSettings.purchaseDuration) or 4500), 1000)
	local startedAt = GetGameTimer()
	local graceMs = math.max(tonumber(validation.sessionGraceMs) or 10000, 0)

	portableSessionCounter = portableSessionCounter + 1

	local sessionId = ('%s:portable-purchase:%s'):format(source, portableSessionCounter)
	local pumpToken

	if occupancySettings.enabled ~= false then
		pumpToken = sessionId
		pumpLeases[pumpKey] = {
			owner = source,
			token = pumpToken,
			model = tonumber(chargerModel),
			position = positionFromPayload(chargerPayload),
			expiresAt = startedAt + duration + graceMs,
		}
		broadcastPumpLease(pumpKey, source)
	end

	portablePurchaseSessions[source] = {
		id = sessionId,
		price = price,
		capacityKwh = portableCapacity(),
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		pumpKey = pumpKey,
		pumpToken = pumpToken,
		chargerModel = chargerModel,
		chargerPayload = chargerPayload,
		startedAt = startedAt,
		duration = duration,
		expiresAt = startedAt + duration + graceMs,
	}

	return {
		id = sessionId,
		price = price,
		capacityKwh = portableCapacity(),
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		duration = duration,
	}
end)

lib.callback.register('ox_fuel:finishPortablePurchase', function(source, sessionId)
	local session = clearPortablePurchaseSession(source, sessionId)

	if not session then return end

	local now = GetGameTimer()

	if now > session.expiresAt or now < session.startedAt + session.duration - 750 then return end
	if not validateFuelCanPump(source, session.chargerModel, session.chargerPayload) then return end
	if not ox_inventory:CanCarryItem(source, portableItemName(), 1) then
		notifyPlayer(source, locale('portable_cannot_carry'))
		return
	end

	local balance = getPaymentBalance(source, session.paymentId) or 0

	if session.price > balance or not chargePayment(source, session.price, session.paymentId) then
		notifyPlayer(source, locale('not_enough_money', math.max(session.price - balance, 0)))
		return
	end

	portableSessionCounter = portableSessionCounter + 1

	local serial = ('EVP-%s-%s-%s'):format(source, os.time(), portableSessionCounter)
	local metadata = applyPortableMetadata({}, serial, session.capacityKwh, nil)
	local added = ox_inventory:AddItem(source, portableItemName(), 1, metadata)

	if added ~= true then
		notifyPlayer(source, locale('portable_cannot_carry'))
		return
	end

	TriggerClientEvent('ox_lib:notify', source, {
		type = 'success',
		description = locale('portable_purchase_success', session.price),
	})

	return {
		price = session.price,
		capacityKwh = session.capacityKwh,
		paymentLabel = session.paymentLabel,
		paymentShortLabel = session.paymentShortLabel,
	}
end)

RegisterNetEvent('ox_fuel:cancelPortablePurchase', function(sessionId)
	clearPortablePurchaseSession(source, sessionId)
end)

local function getFuelCanPrice(hasCan, addedVolume, capacity, grade)
	local petrolCanSettings = config.petrolCan or {}

	if petrolCanSettings.priceFromFuelVolume ~= false then
		local containerPrice = hasCan and 0 or math.max(tonumber(petrolCanSettings.containerPrice) or 0, 0)
		local fuelPrice = math.max(tonumber(addedVolume) or 0, 0) * math.max(tonumber(grade.pricePerGallon) or 0, 0)

		return roundPrice(containerPrice + fuelPrice)
	end

	local defaultGrade = fuelGrades.resolve()
	local gradeMultiplier = defaultGrade.pricePerGallon > 0 and grade.pricePerGallon / defaultGrade.pricePerGallon or 1
	local configuredPrice = hasCan and petrolCanSettings.refillPrice or petrolCanSettings.price
	local volumeMultiplier = hasCan and math.clamp(addedVolume / capacity, 0, 1) or 1

	return roundPrice(math.max(tonumber(configuredPrice) or 0, 0) * volumeMultiplier * gradeMultiplier)
end

lib.callback.register('ox_fuel:prepareFuelCan', function(source, hasCan, gradeId, paymentId, pumpModel, pumpPayload)
	if hasActiveSession(source) then return end

	if type(hasCan) ~= 'boolean' then return end

	local pumpKey = validateFuelCanPump(source, pumpModel, pumpPayload)

	if (pumpModel ~= nil or pumpPayload ~= nil) and not pumpKey then
		notifyPlayer(source, locale('pump_in_use'))
		return
	end

	local requestedGrade = type(gradeId) == 'string' and string.lower(gradeId) or nil
	local grade = fuelGrades.resolve(requestedGrade)

	if requestedGrade and grade.id ~= requestedGrade then return end

	local payment = resolvePayment(source, paymentId or paymentSettings.defaultMethod or 'cash')

	if not payment then return end

	local capacity = math.max(tonumber(config.petrolCan.capacityGallons) or 5.3, 0)

	if capacity <= 0 then return end

	local item
	local ammo = 0
	local currentPremiumRatio = 0

	if hasCan then
		item, ammo, currentPremiumRatio = getPetrolCan(source)

		if not item then return end

		if ammo >= 99.999 then
			notifyPlayer(source, locale('petrolcan_full'))
			return
		end
	elseif not ox_inventory:CanCarryItem(source, 'WEAPON_PETROLCAN', 1) then
		notifyPlayer(source, locale('petrolcan_cannot_carry'))
		return
	end

	local currentVolume = capacity * (ammo / 100)
	local addedVolume = capacity - currentVolume
	local price = getFuelCanPrice(hasCan, addedVolume, capacity, grade)

	if price > payment.balance then
		notifyPlayer(source, locale('not_enough_money', price - payment.balance))
		return
	end

	local premiumRatio = fuelGrades.blend(currentVolume, currentPremiumRatio, addedVolume, grade.premiumRatio)
	local duration = math.max(math.floor(tonumber(config.petrolCan.duration) or 10000), 1000)

	fuelCanSessionCounter = fuelCanSessionCounter + 1

	local sessionId = ('can:%s:%s'):format(source, fuelCanSessionCounter)
	local startedAt = GetGameTimer()
	local pumpToken
	local previousSession = fuelCanSessions[source]

	if previousSession and previousSession.pumpKey then
		releasePumpLease(previousSession.pumpKey, source, previousSession.pumpToken)
	end

	if pumpKey and occupancySettings.enabled ~= false then
		pumpToken = sessionId
		pumpLeases[pumpKey] = {
			owner = source,
			token = pumpToken,
			expiresAt = startedAt + duration + math.max(tonumber(validation.sessionGraceMs) or 10000, 0),
		}
		broadcastPumpLease(pumpKey, source)
	end

	fuelCanSessions[source] = {
		id = sessionId,
		hasCan = hasCan,
		itemSlot = item and item.slot or nil,
		addedVolume = addedVolume,
		capacity = capacity,
		price = price,
		premiumRatio = premiumRatio,
		gradeId = grade.id,
		gradeLabel = grade.label,
		gradeShortLabel = grade.shortLabel,
		pricePerGallon = grade.pricePerGallon,
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		pumpKey = pumpKey,
		pumpToken = pumpToken,
		pumpModel = pumpModel,
		pumpPayload = pumpPayload,
		startedAt = startedAt,
		duration = duration,
		expiresAt = startedAt + duration + math.max(tonumber(validation.sessionGraceMs) or 10000, 0),
	}

	return {
		id = sessionId,
		hasCan = hasCan,
		addedVolume = addedVolume,
		capacity = capacity,
		price = price,
		pricePerGallon = grade.pricePerGallon,
		gradeId = grade.id,
		gradeLabel = grade.label,
		gradeShortLabel = grade.shortLabel,
		paymentId = payment.id,
		paymentLabel = payment.label,
		paymentShortLabel = payment.shortLabel,
		duration = duration,
	}
end)

lib.callback.register('ox_fuel:finishFuelCan', function(source, sessionId)
	local session = fuelCanSessions[source]

	if not session or session.id ~= sessionId then return end

	fuelCanSessions[source] = nil

	if session.pumpKey then
		releasePumpLease(session.pumpKey, source, session.pumpToken)
	end

	local now = GetGameTimer()

	if now > session.expiresAt or now < session.startedAt + session.duration - 750 then return end

	if not validateFuelCanPump(source, session.pumpModel, session.pumpPayload) then return end

	local item

	if session.hasCan then
		item = ox_inventory:GetCurrentWeapon(source)

		if not item or item.name ~= 'WEAPON_PETROLCAN' or item.slot ~= session.itemSlot then return end
	elseif not ox_inventory:CanCarryItem(source, 'WEAPON_PETROLCAN', 1) then
		return
	end

	local balance = getPaymentBalance(source, session.paymentId) or 0

	if session.price > balance or not chargePayment(source, session.price, session.paymentId) then
		notifyPlayer(source, locale('not_enough_money', math.max(session.price - balance, 0)))
		return
	end

	local canBlend = fuelGrades.describeRatio(session.premiumRatio)
	local metadata = {
		durability = 100,
		ammo = 100,
		fuelGrade = canBlend.id,
		fuelPremiumRatio = session.premiumRatio,
	}

	if session.hasCan then
		item.metadata = item.metadata or {}

		for key, value in pairs(metadata) do
			item.metadata[key] = value
		end

		ox_inventory:SetMetadata(source, item.slot, item.metadata)

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('petrolcan_refill', session.price)
		})
	else
		ox_inventory:AddItem(source, 'WEAPON_PETROLCAN', 1, metadata)

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('petrolcan_buy', session.price)
		})
	end

	return {
		price = session.price,
		volume = session.addedVolume,
		capacity = session.capacity,
		gradeLabel = session.gradeLabel,
		gradeShortLabel = session.gradeShortLabel,
		paymentLabel = session.paymentLabel,
		paymentShortLabel = session.paymentShortLabel,
	}
end)

RegisterNetEvent('ox_fuel:cancelFuelCan', function(sessionId)
	local session = fuelCanSessions[source]

	if session and session.id == sessionId then
		fuelCanSessions[source] = nil

		if session.pumpKey then
			releasePumpLease(session.pumpKey, source, session.pumpToken)
		end
	end
end)

local function safeSoundId(value, playerId)
	local id = tostring(value or '')
	local prefix = ('ox_fuel_expanded:%s:'):format(playerId)

	if id == '' then return end
	if id:sub(1, #prefix) ~= prefix then return end
	if not id:match('^[%w_:%-]+$') then return end

	return id
end

local function destroySound(name)
	if not name or GetResourceState('san_andreas_sound') ~= 'started' then return end

	exports.san_andreas_sound:Destroy(-1, name)
end

local function destroyActiveSound(playerId, soundName)
	local sounds = activeLoopSounds[playerId]

	if not sounds then return end

	local name = sounds[soundName]

	if name then
		destroySound(name)
		sounds[soundName] = nil
	end

	if not next(sounds) then
		activeLoopSounds[playerId] = nil
	end
end

local function destroyPlayerSounds(playerId)
	local sounds = activeLoopSounds[playerId]

	if not sounds then return end

	for _, name in pairs(sounds) do
		destroySound(name)
	end

	activeLoopSounds[playerId] = nil
end

RegisterNetEvent('ox_fuel:playSound', function(soundName, payload)
	local source = source
	local sound, sourceSettings = getConfiguredSound(soundName)

	if not sound then return end

	if sourceSettings.soundProvider == 'interact-sound' then
		return TriggerClientEvent('InteractSound_CL:PlayOnOne', source, sound.name, sound.volume)
	end

	if GetResourceState('san_andreas_sound') ~= 'started' then return end

	payload = type(payload) == 'table' and payload or {}
	soundCounter = soundCounter + 1

	local playerPos = playerPosition(source)
	local entityNetId = tonumber(payload.entityNetId)
	local position = positionFromPayload(payload.position) or playerPos
	local allowedDistance = (sourceSettings.maxDistance or 7.5) + 10.0
	local loop = payload.loop == true or sound.loop == true
	local managed = payload.managed == true or sound.managed == true or loop == true
	local name = managed and safeSoundId(payload.soundId, source)

	if playerPos and position and distanceBetween(playerPos, position) > allowedDistance then
		position = playerPos
		entityNetId = nil
	end

	if managed then
		destroyActiveSound(source, soundName)
	end

	if not name then
		name = ('ox_fuel_expanded:%s:%s:%s'):format(soundName, source, soundCounter)
	end

	exports.san_andreas_sound:PlayPositional(-1, {
		name = name,
		url = soundUrl(sound, sourceSettings),
		volume = sound.volume,
		position = position,
		entityNetId = entityNetId and entityNetId > 0 and entityNetId or nil,
		loop = loop,
		maxDistance = sound.maxDistance or sourceSettings.soundMaxDistance or 18.0,
		acousticClass = sound.acousticClass or sourceSettings.soundAcousticClass,
		destroyOnFinish = loop ~= true
	})

	if managed and loop then
		activeLoopSounds[source] = activeLoopSounds[source] or {}
		activeLoopSounds[source][soundName] = name
	end
end)

RegisterNetEvent('ox_fuel:stopSound', function(soundName, payload)
	local source = source

	if not soundName then
		return destroyPlayerSounds(source)
	end

	if not getConfiguredSound(soundName) then return end

	payload = type(payload) == 'table' and payload or {}

	local directSoundId = safeSoundId(payload.soundId, source)

	if directSoundId then
		destroySound(directSoundId)
	end

	destroyActiveSound(source, soundName)
end)

AddEventHandler('playerDropped', function()
	destroyPlayerSounds(source)
	releasePlayerPumps(source)
	releasePortableDeployment(source)
	chaosCooldowns[source] = nil
	fuelingSessions[source] = nil
	chargingSessions[source] = nil
	fuelCanSessions[source] = nil
	portableChargingSessions[source] = nil
	portableRechargeSessions[source] = nil
	clearPortablePurchaseSession(source)
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() then
		local playerIds = {}
		local deployedPlayerIds = {}

		for playerId in pairs(activeLoopSounds) do
			playerIds[#playerIds + 1] = playerId
		end

		for i = 1, #playerIds do
			destroyPlayerSounds(playerIds[i])
		end

		for playerId in pairs(portableDeployments) do
			deployedPlayerIds[#deployedPlayerIds + 1] = playerId
		end

		for i = 1, #deployedPlayerIds do
			releasePortableDeployment(deployedPlayerIds[i])
		end
	elseif resource == 'san_andreas_sound' then
		activeLoopSounds = {}
	end
end)


RegisterNetEvent('ox_fuel:fuelCan', function(hasCan)
	local source = source
	local grade = fuelGrades.resolve()
	local capacity = math.max(tonumber(config.petrolCan.capacityGallons) or 5.3, 0)
	local addedVolume = capacity
	local item

	if capacity <= 0 then return end

	if hasCan then
		local ammo

		item, ammo = getPetrolCan(source)

		if not item then return end

		addedVolume = capacity * ((100 - math.clamp(tonumber(ammo) or 0, 0, 100)) / 100)

		if addedVolume <= 0.0001 then
			return notifyPlayer(source, locale('petrolcan_full'))
		end
	end

	local price = getFuelCanPrice(hasCan, addedVolume, capacity, grade)
	local payment = resolvePayment(source, paymentSettings.defaultMethod or 'cash')

	if not payment or payment.balance < price then
		return notifyPlayer(source, locale('not_enough_money', math.max(price - (payment and payment.balance or 0), 0)))
	end

	if hasCan then
		if not chargePayment(source, price, payment.id) then return end

		item.metadata = item.metadata or {}
		item.metadata.durability = 100
		item.metadata.ammo = 100
		item.metadata.fuelGrade = grade.id
		item.metadata.fuelPremiumRatio = grade.premiumRatio

		ox_inventory:SetMetadata(source, item.slot, item.metadata)

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('petrolcan_refill', price)
		})
	else
		if not ox_inventory:CanCarryItem(source, 'WEAPON_PETROLCAN', 1) then
			return TriggerClientEvent('ox_lib:notify', source, {
				type = 'error',
				description = locale('petrolcan_cannot_carry')
			})
		end

		if not chargePayment(source, price, payment.id) then return end

		ox_inventory:AddItem(source, 'WEAPON_PETROLCAN', 1, {
			durability = 100,
			ammo = 100,
			fuelGrade = grade.id,
			fuelPremiumRatio = grade.premiumRatio,
		})

		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('petrolcan_buy', price)
		})
	end
end)
