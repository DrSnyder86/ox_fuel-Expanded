local pumpSlots = {}

local function normalizedModel(model)
	model = tonumber(model)

	return model and math.floor(model) or nil
end

function pumpSlots.getSlotCount(settings, model)
	if type(settings) ~= 'table' or settings.dualNozzles == false then return 1 end

	model = normalizedModel(model)

	if not model then return 1 end

	local singleNozzleModels = settings.singleNozzleModels

	if type(singleNozzleModels) == 'table' then
		if singleNozzleModels[model] == true or singleNozzleModels[tostring(model)] == true then return 1 end

		for index = 1, #singleNozzleModels do
			if normalizedModel(singleNozzleModels[index]) == model then return 1 end
		end
	end

	return 2
end

function pumpSlots.getLeaseKey(pumpKey, slot)
	if type(pumpKey) ~= 'string' then return end

	slot = math.max(math.floor(tonumber(slot) or 1), 1)

	return ('%s#%s'):format(pumpKey, slot)
end

function pumpSlots.getPreferredSlot(localX)
	return (tonumber(localX) or 0) < 0 and 1 or 2
end

function pumpSlots.getSharedFlowMultiplier(settings)
	local multiplier = type(settings) == 'table' and tonumber(settings.sharedFlowMultiplier) or nil

	return math.min(math.max(multiplier or 0.65, 0.1), 1.0)
end

function pumpSlots.canSetConnectorTaken(lease, playerId, token, chargerModel, now)
	return type(lease) == 'table' and type(token) == 'string'
		and lease.owner == playerId and lease.token == token
		and normalizedModel(lease.model) == normalizedModel(chargerModel)
		and normalizedModel(chargerModel) ~= nil
		and type(lease.expiresAt) == 'number' and lease.expiresAt >= now
end

return pumpSlots
