local config = require 'config'

local settings = config.electric or {}
local configured = settings.vehicles or {}
local profiles = {}

for model, profile in pairs(configured) do
	local hash = type(model) == 'number' and model or joaat(model)

	if type(profile) == 'number' then
		profile = { batteryCapacityKwh = profile }
	end

	if type(profile) == 'table' then
		profiles[hash] = {
			batteryCapacityKwh = math.max(tonumber(profile.batteryCapacityKwh) or tonumber(settings.defaultBatteryCapacityKwh) or 75.0, 0),
			consumptionRate = math.max(tonumber(profile.consumptionRate) or 1.0, 0),
		}
	end
end

local electricProfiles = {}

function electricProfiles.isElectricModel(model)
	return settings.enabled ~= false and profiles[tonumber(model)] ~= nil
end

function electricProfiles.resolve(model)
	if settings.enabled == false then return end

	return profiles[tonumber(model)]
end

function electricProfiles.getBatteryCapacity(model)
	local profile = electricProfiles.resolve(model)

	return profile and profile.batteryCapacityKwh or nil
end

return electricProfiles
