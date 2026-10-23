local config = require 'config'
local settings = config.electric and config.electric.stationDisplay or {}
local ronSettings = config.ronPump and config.ronPump.stationDisplay or {}
local display = {}
local stations = {}
local surfaces = {}
local nextId = 0
local activeEntity, activeSlot
local latestData, checkoutData
local stopping = false
local presented = false
local renderDistance = math.max(tonumber(settings.renderDistance) or 14.0, 1.0)
local inputDistance = math.min(math.max(tonumber(settings.inputDistance) or 3.0, 0.5), renderDistance)
local maxStations = math.min(math.max(math.floor(tonumber(settings.maxStations) or 2), 1), 4)

local function copy(data)
	local result = {}
	for key, value in pairs(data or {}) do result[key] = value end
	return result
end

local function idlePayload(slot, profile)
	if profile and profile.mode == 'pump' then
		local liters = (config.fuelMeter or {}).unit == 'liters'
		local price = tonumber((config.fueling or {}).pricePerGallon) or 0
		return { action = 'show', mode = 'pump', state = 'ready', label = locale('fuel_meter_ready'),
			brand = 'RON', logo = 'prop_gas_pump_1a', theme = 'modern', variant = 'ron-modern', accent = '#ef8b32',
			unit = liters and 'liters' or 'gallons', unitLabel = locale(liters and 'fuel_meter_liters' or 'fuel_meter_gallons'),
			saleLabel = locale('fuel_meter_sale'), levelLabel = locale('fuel_meter_tank_level'),
			addedVolume = 0, cost = 0, unitPrice = liters and price / 3.785411784 or price,
			currency = (config.fuelMeter or {}).currency or '$' }
	end
	return {
		action = 'show', mode = 'charging', state = 'ready',
		label = locale('charge_meter_ready'), brand = ('SENTINEL | %s'):format(slot == 1 and 'A' or 'B'),
		logo = 'electric_charger', theme = 'modern', variant = 'charge-modern', accent = '#19b9ff',
		unit = 'kilowatt-hours', addedVolume = 0, cost = 0, powerKw = 0,
		currency = config.fuelMeter and config.fuelMeter.currency or '$',
	}
end

local function message(surface, data)
	if surface and surface.ready and surface.dui then SendDuiMessage(surface.dui, json.encode(data)) end
end

local function replay(surface)
	message(surface, { action = 'hide' })
	if surface.entity == activeEntity and surface.slot == activeSlot and latestData then
		local data = copy(latestData)
		data.action = 'show'
		message(surface, data)
		if checkoutData then message(surface, checkoutData) end
	else
		message(surface, idlePayload(surface.slot, stations[surface.entity] and stations[surface.entity].profile))
	end
end

local function destroySurface(surface)
	-- Remove the handle before destroying CEF, including during an unfinished load.
	local dui = surface.dui
	surface.dui, surface.ready = nil, false
	surfaces[surface.id] = nil
	if dui then DestroyDui(dui) end
end

local function clearSurfaces(station)
	for _, surface in pairs(station.surfaces) do destroySurface(surface) end
	station.surfaces = {}
end

function display.register(entity)
	if stopping or not entity or not DoesEntityExist(entity) or stations[entity] then return end
	local model = GetEntityModel(entity)
	local profile = settings.enabled == true and model == settings.model and settings
		or config.ronPump and config.ronPump.enabled == true and ronSettings.enabled == true and model == ronSettings.model and ronSettings
	if not profile then return end
	stations[entity] = { entity = entity, profile = profile, surfaces = {}, retryAt = 0 }
end

function display.unregister(entity)
	local station = stations[entity]
	if not station then return end
	clearSurfaces(station)
	stations[entity] = nil
end

function display.setPump(entity, slot)
	local station = stations[entity]
	if station and station.profile.useApproachSide == true then
		local camera = GetGameplayCamCoord()
		local approach = GetOffsetFromEntityGivenWorldCoords(entity, camera.x, camera.y, camera.z)
		slot = approach.y > 0 and 2 or 1
	end
	if activeEntity == entity and activeSlot == slot then return end
	local previous = stations[activeEntity]
	activeEntity = stations[entity] and entity or nil
	activeSlot = tonumber(slot) == 2 and 2 or 1
	latestData, checkoutData = nil, nil
	if previous then
		for _, surface in pairs(previous.surfaces) do replay(surface) end
	end
end

function display.clearPump()
	display.setPump(nil, 1)
end

function display.hasPump()
	return stations[activeEntity] ~= nil
end

function display.getMode()
	local station = stations[activeEntity]
	return station and station.profile.mode or 'charging'
end

function display.usesModelOnly()
	local station = stations[activeEntity]
	return station ~= nil and station.profile.hudFallback ~= true
end

function display.isReady()
	local station = stations[activeEntity]
	local surface = station and station.surfaces[activeSlot]
	return surface ~= nil and surface.ready == true and DoesEntityExist(activeEntity)
end

function display.awaitReady(timeoutMs)
	local entity, slot = activeEntity, activeSlot
	local deadline = GetGameTimer() + (timeoutMs or 6000)
	while activeEntity == entity and activeSlot == slot and display.hasPump() and not stopping do
		if display.isReady() then return true end
		if GetGameTimer() >= deadline then break end
		Wait(50)
	end
	return false
end

local function canInput()
	if not display.isReady() then return false end
	local profile = stations[activeEntity].profile
	local screen = profile.screens[activeSlot]
	local center = GetOffsetFromEntityInWorldCoords(activeEntity, screen.x, screen.y, screen.z)
	return #(GetGameplayCamCoord() - center) <= (tonumber(profile.inputDistance) or inputDistance)
end

function display.canPresent()
	local station = stations[activeEntity]
	local surface = station and station.surfaces[activeSlot]
	if not surface or not surface.ready or not DoesEntityExist(activeEntity) then return false end
	local profile = station.profile
	local screen = profile.screens[activeSlot]
	local center = GetOffsetFromEntityInWorldCoords(activeEntity, screen.x, screen.y, screen.z)
	local camera = GetGameplayCamCoord()
	local localCamera = GetOffsetFromEntityGivenWorldCoords(activeEntity, camera.x, camera.y, camera.z)
	local left = GetOffsetFromEntityInWorldCoords(activeEntity, screen.x - screen.width * 0.5, screen.y, screen.z)
	local right = GetOffsetFromEntityInWorldCoords(activeEntity, screen.x + screen.width * 0.5, screen.y, screen.z)
	local leftVisible, leftX = GetScreenCoordFromWorldCoord(left.x, left.y, left.z)
	local rightVisible, rightX = GetScreenCoordFromWorldCoord(right.x, right.y, right.z)
	local resolutionX = GetActiveScreenResolution()
	local minimumPixels = (tonumber(profile.minimumScreenPixels) or 130) * (presented and 0.85 or 1.0)
	local readable = leftVisible and rightVisible and math.abs(rightX - leftX) * resolutionX >= minimumPixels
	local facing = screen.back and localCamera.y > screen.y or not screen.back and localCamera.y < screen.y
	return #(camera - center) <= (checkoutData and (tonumber(profile.inputDistance) or inputDistance) or (tonumber(profile.renderDistance) or renderDistance))
		and facing
		and readable
		and IsSphereVisible(center.x, center.y, center.z, 0.18)
end

function display.getHudPayload()
	if checkoutData then return copy(checkoutData) end
	if not latestData then return { action = 'hide' } end
	local data = copy(latestData)
	data.action = 'show'
	return data
end

function display.send(data)
	local station = stations[activeEntity]
	if not station then return false end
	local action = data.action
	if action == 'hide' then
		latestData, checkoutData = nil, nil
	elseif action == 'options' then
		checkoutData = copy(data)
	elseif action == 'closeOptions' then
		checkoutData = nil
	elseif action == 'show' or action == 'update' or action == 'finish' then
		latestData = action == 'show' and {} or latestData or {}
		for key, value in pairs(data) do latestData[key] = value end
	end
	local surface = station.surfaces[activeSlot]
	if surface then
		if action == 'hide' then
			message(surface, { action = 'hide' })
			message(surface, idlePayload(activeSlot, station.profile))
		else message(surface, data) end
	end
	return display.usesModelOnly() or display.canPresent()
end

RegisterNUICallback('stationReady', function(data, callback)
	local surface = surfaces[tonumber(data and data.id)]
	if surface and surface.dui and not stopping then surface.browserReady = true end
	callback({ ok = surface ~= nil })
end)

local function createSurface(station, slot)
	nextId = nextId + 1
	local surface = { id = nextId, slot = slot, entity = station.entity }
	station.surfaces[slot] = surface
	surfaces[surface.id] = surface
	local resource = GetCurrentResourceName()
	local profile = station.profile
	local surfaceType = profile.mode == 'pump' and 'pump' or 'station'
	local url = ('https://cfx-nui-%s/web/index.html?surface=%s&resource=%s&id=%s'):format(resource, surfaceType, resource, surface.id)
	local ok, dui = pcall(CreateDui, url, tonumber(profile.textureWidth) or 512, tonumber(profile.textureHeight) or 640)
	if not ok or not dui then
		destroySurface(surface)
		station.surfaces[slot] = nil
		station.retryAt = GetGameTimer() + 30000
		return
	end
	surface.dui = dui
	CreateThread(function()
		local timeout = GetGameTimer() + 5000
		while not stopping and surface.dui and (not IsDuiAvailable(dui) or not surface.browserReady) and GetGameTimer() < timeout do Wait(50) end
		if stopping or not surface.dui then return end
		if not surface.browserReady or not IsDuiAvailable(dui) then
			destroySurface(surface)
			station.surfaces[slot] = nil
			station.retryAt = GetGameTimer() + 30000
			if not station.warned then
				print('^3[ox_fuel] Physical station/pump screen unavailable; check the NUI/DUI resource files.^0')
				station.warned = true
			end
			return
		end
		-- Reuse the same runtime dictionary after streaming a station out and back in.
		surface.dictionary = ('ox_fuel_station_%s_%s'):format(station.entity, slot)
		local txd = CreateRuntimeTxd(surface.dictionary)
		CreateRuntimeTextureFromDuiHandle(txd, 'screen', GetDuiHandle(dui))
		surface.ready = true
		replay(surface)
	end)
end

local function triangle(surface, a, b, c, ua, va, ub, vb, uc, vc)
	Citizen.InvokeNative(0x736D7AA1B750856B,
		a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z,
		255.0, 255.0, 255.0, 255, 255.0, 255.0, 255.0, 255, 255.0, 255.0, 255.0, 255,
		surface.dictionary, 'screen', ua, va, 1.0, ub, vb, 1.0, uc, vc, 1.0)
end

local function render(surface)
	local s = stations[surface.entity].profile.screens[surface.slot]
	local x, y, z, w, h = s.x, s.y, s.z, s.width * (s.back and -0.5 or 0.5), s.height * 0.5
	local a = GetOffsetFromEntityInWorldCoords(surface.entity, x - w, y, z + h)
	local b = GetOffsetFromEntityInWorldCoords(surface.entity, x - w, y, z - h)
	local c = GetOffsetFromEntityInWorldCoords(surface.entity, x + w, y, z - h)
	local d = GetOffsetFromEntityInWorldCoords(surface.entity, x + w, y, z + h)
	triangle(surface, a, b, c, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0)
	triangle(surface, a, c, d, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0)
end

local controls = { [172] = 'up', [173] = 'down', [174] = 'left', [175] = 'right', [191] = 'confirm', [177] = 'cancel' }

if settings.enabled == true or config.ronPump and config.ronPump.enabled == true and ronSettings.enabled == true then
	CreateThread(function()
		while not stopping do
			local nearby = {}
			local camera = GetGameplayCamCoord()
			for entity, station in pairs(stations) do
				if not DoesEntityExist(entity) then display.unregister(entity)
				else
					local distance = #(GetEntityCoords(entity) - camera)
					if distance <= (tonumber(station.profile.renderDistance) or renderDistance) then nearby[#nearby + 1] = { station = station, distance = entity == activeEntity and -1 or distance } end
				end
			end
			table.sort(nearby, function(a, b) return a.distance < b.distance end)
			local selected = {}
			for i = 1, math.min(#nearby, maxStations) do selected[nearby[i].station.entity] = true end
			for entity, station in pairs(stations) do
				if not selected[entity] then clearSurfaces(station)
				elseif GetGameTimer() >= station.retryAt then
					for slot in pairs(station.profile.screens or {}) do
						if not station.surfaces[slot] then createSurface(station, slot) end
					end
				end
			end
			Wait(250)
		end
	end)

	CreateThread(function()
		while not stopping do
			local drew = false
			for _, surface in pairs(surfaces) do
				if surface.ready and DoesEntityExist(surface.entity) then render(surface) drew = true end
			end
			local inWorld = display.canPresent()
			if inWorld ~= presented then
				presented = inWorld
				if display.onPresentationChanged then display.onPresentationChanged(inWorld) end
			end
			if checkoutData and (inWorld or display.usesModelOnly()) then
				local station = stations[activeEntity]
				for control, name in pairs(controls) do
					-- Backspace can cancel even after walking away or while CEF is unavailable.
					if name == 'cancel' or canInput() then
						DisableControlAction(0, control, true)
						if IsDisabledControlJustPressed(0, control) then
							if name == 'cancel' and display.onCheckoutCancel then display.onCheckoutCancel()
							else message(station.surfaces[activeSlot], { action = 'worldInput', control = name }) end
						end
					end
				end
			end
			Wait(drew and 0 or 150)
		end
	end)
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource ~= GetCurrentResourceName() then return end
	stopping = true
	for entity in pairs(stations) do display.unregister(entity) end
end)

return display
