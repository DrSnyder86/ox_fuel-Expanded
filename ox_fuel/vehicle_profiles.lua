local config = require 'config'
local settings = config.vehicleProfiles or {}
local profiles = {}

local litersPerUsGallon = 3.785411784

local function numberOrFallback(value, fallback, minimum)
	value = tonumber(value)

	if value == nil or value < (minimum or 0) then
		return fallback
	end

	return value
end

function profiles.normalizeClass(vehicleClass)
	vehicleClass = tonumber(vehicleClass)

	if not vehicleClass or vehicleClass % 1 ~= 0 or vehicleClass < 0 or vehicleClass > 22 then return end

	return math.floor(vehicleClass)
end

function profiles.resolve(model, vehicleClass)
	local defaults = settings.default or {}
	local normalizedClass = profiles.normalizeClass(vehicleClass)
	local classProfile = normalizedClass and settings.classes and settings.classes[normalizedClass] or nil
	local modelProfile = model and settings.models and settings.models[model] or nil
	local tankCapacity = numberOrFallback(
		modelProfile and modelProfile.tankCapacityGallons,
		numberOrFallback(classProfile and classProfile.tankCapacityGallons, numberOrFallback(defaults.tankCapacityGallons, 20.0), 0),
		0
	)
	local consumptionRate = numberOrFallback(
		modelProfile and modelProfile.consumptionRate,
		numberOrFallback(classProfile and classProfile.consumptionRate, numberOrFallback(defaults.consumptionRate, 1.0), 0),
		0
	)

	return {
		class = normalizedClass,
		name = modelProfile and modelProfile.name or classProfile and classProfile.name or defaults.name or 'Default',
		tankCapacityGallons = tankCapacity,
		consumptionRate = consumptionRate,
	}
end

function profiles.isClassCompatibleWithType(vehicleClass, vehicleType)
	if vehicleType == 'bike' then return vehicleClass == 8 or vehicleClass == 13 end
	if vehicleType == 'boat' or vehicleType == 'submarine' then return vehicleClass == 14 end
	if vehicleType == 'heli' then return vehicleClass == 15 end
	if vehicleType == 'plane' then return vehicleClass == 16 end
	if vehicleType == 'train' then return vehicleClass == 21 end
	if vehicleType == 'automobile' then
		return vehicleClass <= 7
			or (vehicleClass >= 9 and vehicleClass <= 12)
			or (vehicleClass >= 17 and vehicleClass <= 20)
			or vehicleClass == 22
	end

	return true
end

function profiles.gallonsToLiters(gallons)
	return (tonumber(gallons) or 0) * litersPerUsGallon
end

function profiles.litersToGallons(liters)
	return (tonumber(liters) or 0) / litersPerUsGallon
end

return profiles
