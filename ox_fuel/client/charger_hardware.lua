local config = require 'config'
local pumpSlots = require 'pump_slots'
local settings = config.electric or {}
local dockSettings = settings.docking or {}
local portableSettings = settings.portable or {}
local lighting = settings.stationLighting or {}
local ron = config.ronPump or {}
local ronDock = ron.docking or {}
local hardware = {}
local sources = {}
local owners, takenSockets = {}, {}
local stopping = false
local interaction
local targetName = 'ox_fuel:sentinelDockConnector'
local distance = math.max(tonumber(dockSettings.renderDistance) or 30, tonumber(ronDock.renderDistance) or 0, 3)
local maxSources = math.max(math.min(math.max(math.floor(tonumber(dockSettings.maxSources) or 4), math.floor(tonumber(ronDock.maxSources) or 0)), 8), 1)
local lightingSources = math.min(math.max(math.floor(tonumber(lighting.maxSources) or 2), 1), 4)

local function identity(entity)
	local coords = GetEntityCoords(entity)
	local precision = math.max(math.floor(tonumber((config.pumpOccupancy or {}).coordinatePrecision) or 10), 1)
	local function quantize(value)
		value = value * precision
		return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
	end
	return ('%s:%s:%s:%s'):format(GetEntityModel(entity), quantize(coords.x), quantize(coords.y), quantize(coords.z))
end

local function clearSlot(slot)
	slot.generation = slot.generation + 1
	slot.loading = nil
	if slot.target and slot.connector and config.ox_target then
		pcall(function() exports.ox_target:removeLocalEntity(slot.connector, { targetName }) end)
	end
	slot.target = nil
	for _, key in ipairs({ 'cable', 'connector' }) do
		local object = slot[key]
		slot[key] = nil
		if object and DoesEntityExist(object) then
			DetachEntity(object, true, true)
			DeleteEntity(object)
		end
	end
end

local function isTaken(record, slot)
	if slot.localTaken ~= nil then return slot.localTaken end
	if record.kind == 'portable' then return Entity(record.entity).state.oxFuelPortableConnectorTaken == true end
	return takenSockets[slot.key] == true
end

local function valid(record, slot, generation)
	return not stopping and sources[record.entity] == record and record.enabled
		and DoesEntityExist(record.entity) and GetEntityModel(record.entity) == record.model
		and not (record.kind == 'portable' and Entity(record.entity).state.oxFuelPortableDamaged == true)
		and slot.generation == generation and not isTaken(record, slot)
end

local function registerTarget(record, slot)
	if not config.ox_target or not interaction or not slot.connector or slot.target then return end
	exports.ox_target:addLocalEntity(slot.connector, {{
		name = targetName,
		distance = tonumber(portableSettings.interactionDistance) or 2.5,
		icon = record.kind == 'pump' and 'fas fa-gas-pump' or 'fas fa-plug',
		label = locale(record.kind == 'pump' and 'take_nozzle' or (record.kind == 'portable' and 'portable_take_connector' or 'take_charge_connector')),
		canInteract = function()
			local owner = owners[slot.key]
			local available = record.kind == 'portable' or not owner or owner == GetPlayerServerId(PlayerId())
			return record.enabled and available and not isTaken(record, slot) and interaction.canTake(record.entity, record.kind, slot.index)
		end,
		onSelect = function() interaction.take(record.entity, record.kind, slot.index) end,
	}})
	slot.target = true
end

local function cableOffset(record, slot)
	if record.kind == 'pump' then return slot.profile.anchor or {} end
	if record.kind == 'portable' then return portableSettings.cableOffset or {} end
	local base = settings.chargerCableOffset or {}
	local extra = settings.chargerCableSlotOffsets and settings.chargerCableSlotOffsets[slot.index] or {}
	return { x = (base.x or 0) + (extra.x or 0), y = (base.y or 0) + (extra.y or 0), z = (base.z or 0) + (extra.z or 0) }
end

local function createAttached(record, model, offset, rotation, targetable)
	local coords = GetOffsetFromEntityInWorldCoords(record.entity, offset.x or 0, offset.y or 0, offset.z or 0)
	local object = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
	if not object or object == 0 then return end
	SetEntityAsMissionEntity(object, true, true)
	SetEntityInvincible(object, true)
	SetEntityCollision(object, targetable == true, false)
	AttachEntityToEntity(object, record.entity, 0, offset.x or 0, offset.y or 0, offset.z or 0,
		rotation.x or 0, rotation.y or 0, rotation.z or 0, false, false, false, false, 0, true)
	FreezeEntityPosition(object, true)
	return object
end

local function ensureSlot(record, slot)
	if not valid(record, slot, slot.generation) then return end
	if slot.connector and DoesEntityExist(slot.connector) then registerTarget(record, slot) return slot.connector end
	if slot.loading or GetGameTimer() < (slot.retryAt or 0) then return end
	local generation = slot.generation
	slot.loading = generation
	local models = { record.nozzleModel }
	if record.cableEnabled and slot.profile.cableModel then models[#models + 1] = slot.profile.cableModel end
	for i = 1, #models do
		local ok = pcall(lib.requestModel, models[i], 5000)
		if not ok or not valid(record, slot, generation) then
			for j = 1, i do SetModelAsNoLongerNeeded(models[j]) end
			if slot.loading == generation then slot.loading = nil end
			if not ok then slot.retryAt = GetGameTimer() + 15000 end
			return
		end
	end
	slot.connector = createAttached(record, record.nozzleModel, slot.profile.offset or {}, slot.profile.rotation or {}, true)
	if slot.connector and #models > 1 then
		slot.cable = createAttached(record, slot.profile.cableModel, cableOffset(record, slot), {})
	end
	for i = 1, #models do SetModelAsNoLongerNeeded(models[i]) end
	if slot.loading == generation then slot.loading = nil end
	if not slot.connector then slot.retryAt = GetGameTimer() + 15000 end
	registerTarget(record, slot)
	return slot.connector
end

function hardware.register(entity, kind)
	if stopping or not entity or not DoesEntityExist(entity) then return end
	if sources[entity] then return end
	kind = kind or 'station'
	local model = GetEntityModel(entity)
	local profiles
	if kind == 'pump' then
		if ron.enabled ~= true or model ~= ron.model then return end
		profiles = ronDock.enabled == true and ronDock.slots or {}
	elseif settings.enabled == false then return
	elseif kind == 'portable' then
		if portableSettings.enabled == false then return end
		local portableDock = portableSettings.docking or {}
		if portableDock.enabled ~= true or model ~= portableSettings.groundModel then return end
		profiles = { [1] = portableDock }
	else
		local hasDocks = dockSettings.enabled == true and model == dockSettings.model
		if not hasDocks and not (lighting.enabled == true and model == lighting.model) then return end
		profiles = hasDocks and dockSettings.slots or {}
	end
	local record = { entity = entity, kind = kind, model = model, enabled = true, slots = {},
		nozzleModel = kind == 'pump' and config.nozzle.model or settings.connectorModel,
		cableEnabled = kind == 'pump' and config.nozzle.hose ~= false or kind ~= 'pump' and settings.cable ~= false,
		lighting = kind == 'pump' and ron.lighting or lighting }
	local key = identity(entity)
	for index, profile in pairs(profiles or {}) do
		record.slots[index] = { index = index, key = pumpSlots.getLeaseKey(key, index), profile = profile, generation = 0 }
	end
	sources[entity] = record
end

function hardware.unregister(entity)
	local record = sources[entity]
	if not record then return end
	for _, slot in pairs(record.slots) do clearSlot(slot) end
	sources[entity] = nil
end

function hardware.setEnabled(entity, enabled)
	local record = sources[entity]
	if not record then return end
	record.enabled = enabled == true
	if not record.enabled then for _, slot in pairs(record.slots) do clearSlot(slot) end end
end

function hardware.setOccupancy(key, owner, taken)
	owners[key], takenSockets[key] = owner or nil, taken == true or nil
	local player = GetPlayerServerId(PlayerId())
	for _, record in pairs(sources) do
		for _, slot in pairs(record.slots) do
			if slot.key == key then
				if not owner or owner ~= player or (taken ~= true and slot.localTaken == false) then slot.localTaken = nil end
				if isTaken(record, slot) then clearSlot(slot) end
			end
		end
	end
end

function hardware.setSnapshot(snapshot, connectors)
	owners, takenSockets = snapshot or {}, connectors or {}
	for _, record in pairs(sources) do
		for _, slot in pairs(record.slots) do
			if record.kind ~= 'portable' and owners[slot.key] ~= GetPlayerServerId(PlayerId()) then slot.localTaken = nil end
			if isTaken(record, slot) then clearSlot(slot) end
		end
	end
end

function hardware.setInteraction(callbacks)
	interaction = callbacks
	for _, record in pairs(sources) do for _, slot in pairs(record.slots) do registerTarget(record, slot) end end
end

function hardware.take(entity, index)
	local record = sources[entity]
	local slot = record and record.slots[index or 1]
	if not slot then return end
	local object = ensureSlot(record, slot)
	if not object or not DoesEntityExist(object) then return end
	-- Transfer this exact visible entity to charging.lua; cleanup must no longer own it.
	if slot.target and config.ox_target then exports.ox_target:removeLocalEntity(object, { targetName }) end
	slot.target, slot.connector = nil, nil
	clearSlot(slot)
	slot.localTaken = true
	DetachEntity(object, true, true)
	FreezeEntityPosition(object, false)
	return object
end

function hardware.restore(entity, index)
	local record = sources[entity]
	local slot = record and record.slots[index or 1]
	if slot then slot.localTaken = false end
end

function hardware.isBusy(entity)
	local record = sources[entity]
	if record then
		for _, slot in pairs(record.slots) do
			if owners[slot.key] or isTaken(record, slot) then return true end
		end
	end
	return false
end

CreateThread(function()
	if settings.enabled == false and ron.enabled ~= true then return end
	local nextDiscovery = 0
	while not stopping do
		local now = GetGameTimer()
		local portableDock = portableSettings.docking or {}
		if portableDock.enabled == true and now >= nextDiscovery then
			for _, entity in ipairs(GetGamePool('CObject')) do
				if DoesEntityExist(entity) and GetEntityModel(entity) == portableSettings.groundModel then hardware.register(entity, 'portable') end
			end
			nextDiscovery = now + 2000
		end
		local nearby = {}
		local camera = GetGameplayCamCoord()
		for entity, record in pairs(sources) do
			if not DoesEntityExist(entity) or GetEntityModel(entity) ~= record.model then hardware.unregister(entity)
			else
				local range = #(GetEntityCoords(entity) - camera)
				if record.enabled and range <= distance then nearby[#nearby + 1] = { record = record, distance = range } end
			end
		end
		table.sort(nearby, function(a, b) return a.distance < b.distance end)
		local selected = {}
		for i = 1, math.min(#nearby, maxSources) do selected[nearby[i].record.entity] = true end
		for entity, record in pairs(sources) do
			local damaged = record.kind == 'portable' and Entity(entity).state.oxFuelPortableDamaged == true
			for _, slot in pairs(record.slots) do
				if not selected[entity] or damaged or isTaken(record, slot) then
					if slot.connector or slot.cable or slot.loading then clearSlot(slot) end
				elseif not slot.connector and not slot.loading then
					CreateThread(function() ensureSlot(record, slot) end)
				end
			end
		end
		Wait(250)
	end
end)

CreateThread(function()
	if settings.enabled == false and ron.enabled ~= true then return end
	while not stopping do
		local camera, nearby, drew = GetGameplayCamCoord(), {}, false
		local hour = GetClockHours()
		local night = hour >= 19 or hour < 7
		for entity, record in pairs(sources) do
			local sourceLight = record.lighting or {}
			if sourceLight.enabled == true and (sourceLight.nightOnly == false or night) then
				if record.enabled and record.kind ~= 'portable' and DoesEntityExist(entity)
					and GetEntityModel(entity) == sourceLight.model
					and #(GetEntityCoords(entity) - camera) <= (tonumber(sourceLight.renderDistance) or 12)
				then
					nearby[#nearby + 1] = { entity = entity, profile = sourceLight, distance = #(GetEntityCoords(entity) - camera) }
				end
			end
		end
		table.sort(nearby, function(a, b) return a.distance < b.distance end)
		for index = 1, math.min(#nearby, lightingSources) do
			local source = nearby[index]
			local fade = math.min(math.max(((tonumber(source.profile.renderDistance) or 12) - source.distance) / 3, 0), 1)
			local drawn = 0
			for _, light in ipairs(source.profile.lights or {}) do
				local offset, colour, span = light.offset or {}, light.colour or {}, light.span or {}
				local samples = math.min(math.max(math.floor(tonumber(light.samples) or 1), 1), 3)
				for sample = 1, samples do
					if drawn >= 12 then break end
					-- Small overlapping pools follow the diffuser rather than one bright center.
					local fraction = samples == 1 and 0 or (sample - 1) / (samples - 1) - 0.5
					local point = GetOffsetFromEntityInWorldCoords(source.entity,
						(offset.x or 0) + (span.x or 0) * fraction,
						(offset.y or 0) + (span.y or 0) * fraction,
						(offset.z or 0) + (span.z or 0) * fraction)
					DrawLightWithRange(point.x, point.y, point.z, colour.r or 36, colour.g or 173, colour.b or 197,
						tonumber(light.range) or 0.65, (tonumber(light.intensity) or 0.25) * fade)
					drawn, drew = drawn + 1, true
				end
				if drawn >= 12 then break end
			end
		end
		Wait(drew and 0 or 500)
	end
end)

AddEventHandler('onClientResourceStop', function(resource)
	if resource ~= GetCurrentResourceName() then return end
	stopping = true
	for entity in pairs(sources) do hardware.unregister(entity) end
end)

return hardware
