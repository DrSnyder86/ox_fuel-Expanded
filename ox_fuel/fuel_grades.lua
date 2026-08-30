local config = require 'config'

local settings = config.fueling or {}
local configuredGrades = settings.grades or {}
local fuelGrades = {}

local function clampRatio(value)
	return math.clamp(tonumber(value) or 0, 0, 1)
end

local function configuredGrade(id)
	id = type(id) == 'string' and string.lower(id) or nil

	if id and type(configuredGrades[id]) == 'table' then
		return id, configuredGrades[id]
	end

	local fallbackId = type(settings.defaultGrade) == 'string' and string.lower(settings.defaultGrade) or 'regular'
	local fallback = configuredGrades[fallbackId]

	if type(fallback) == 'table' then return fallbackId, fallback end

	return 'regular', {
		label = 'Regular',
		shortLabel = 'REG',
		pricePerGallon = settings.pricePerGallon,
		premiumRatio = 0,
		consumptionMultiplier = 1,
	}
end

function fuelGrades.resolve(id)
	local gradeId, grade = configuredGrade(id)

	return {
		id = gradeId,
		label = tostring(grade.label or gradeId),
		shortLabel = tostring(grade.shortLabel or grade.label or gradeId):upper(),
		octane = tonumber(grade.octane),
		pricePerGallon = math.max(tonumber(grade.pricePerGallon) or tonumber(settings.pricePerGallon) or 0, 0),
		premiumRatio = clampRatio(grade.premiumRatio),
		consumptionMultiplier = math.max(tonumber(grade.consumptionMultiplier) or 1, 0),
	}
end

function fuelGrades.getAll()
	local output = {}
	local seen = {}
	local order = settings.gradeOrder or {}

	for i = 1, #order do
		local id = type(order[i]) == 'string' and string.lower(order[i]) or nil

		if id and configuredGrades[id] and not seen[id] then
			seen[id] = true
			output[#output + 1] = fuelGrades.resolve(id)
		end
	end

	for id in pairs(configuredGrades) do
		if type(id) == 'string' and not seen[id] then
			seen[id] = true
			output[#output + 1] = fuelGrades.resolve(id)
		end
	end

	if #output == 0 then output[1] = fuelGrades.resolve() end

	return output
end

function fuelGrades.blend(currentVolume, currentRatio, addedVolume, addedRatio)
	currentVolume = math.max(tonumber(currentVolume) or 0, 0)
	addedVolume = math.max(tonumber(addedVolume) or 0, 0)

	local totalVolume = currentVolume + addedVolume

	if totalVolume <= 0.0001 then return 0 end

	local premiumVolume = (currentVolume * clampRatio(currentRatio)) + (addedVolume * clampRatio(addedRatio))

	return clampRatio(premiumVolume / totalVolume)
end

function fuelGrades.getConsumptionMultiplier(premiumRatio)
	local premiumGrade = fuelGrades.resolve(settings.premiumGrade or 'premium')
	local ratio = clampRatio(premiumRatio)

	return 1 + (ratio * (premiumGrade.consumptionMultiplier - 1))
end

function fuelGrades.describeRatio(premiumRatio)
	local ratio = clampRatio(premiumRatio)

	if ratio <= 0.001 then return fuelGrades.resolve(settings.defaultGrade) end
	if ratio >= 0.999 then return fuelGrades.resolve(settings.premiumGrade or 'premium') end

	return {
		id = 'blend',
		label = 'Blend',
		shortLabel = ('%d%% PREM'):format(math.floor((ratio * 100) + 0.5)),
		pricePerGallon = 0,
		premiumRatio = ratio,
		consumptionMultiplier = fuelGrades.getConsumptionMultiplier(ratio),
	}
end

function fuelGrades.clampRatio(value)
	return clampRatio(value)
end

return fuelGrades
