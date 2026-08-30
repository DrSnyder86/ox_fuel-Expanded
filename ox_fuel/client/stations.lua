local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local stations = lib.load 'data.stations'

if config.showBlips == 2 then
	for station in pairs(stations) do utils.createBlip(station) end
end

if config.ox_target and config.showBlips ~= 1 then return end

---@param point CPoint
local function onEnterStation(point)
	if config.showBlips == 1 and not point.blip then
		point.blip = utils.createBlip(point.coords)
	end
end

---@param point CPoint
local function nearbyStation(point)
	if point.currentDistance > 15 then return end

	local pumps = point.pumps
	local pumpDistance
	local textShown = false

	for i = 1, #pumps do
		local pump = pumps[i]
		pumpDistance = #(cache.coords - pump)

		if pumpDistance <= 3 then
			state.nearestPump = pump
			textShown = false

			repeat
				local playerCoords = GetEntityCoords(cache.ped)
				pumpDistance = #(playerCoords - pump)

				local text = nil

				if cache.vehicle then
					text = locale('textui_gas_station')
				elseif not state.isFueling then
					local vehicleInRange = state.lastVehicle ~= 0 and
						#(GetEntityCoords(state.lastVehicle) - playerCoords) <= 3

					if vehicleInRange then
						text = locale('textui_fuel_pump')
					elseif config.petrolCan.enabled then
						text = locale('textui_fuel_pump')
					end
				end

				if text and not textShown then
					lib.showTextUI(text, {
						icon = 'gas-pump'
					})
					textShown = true
				elseif not text and textShown then
					lib.hideTextUI()
					textShown = false
				end

				Wait(200)
			until pumpDistance > 3

			if textShown then
				lib.hideTextUI()
			end

			state.nearestPump = nil
			return
		end
	end
end

---@param point CPoint
local function onExitStation(point)
	if point.blip then
		point.blip = RemoveBlip(point.blip)
	end
end

for station, pumps in pairs(stations) do
	lib.points.new({
		coords = station,
		distance = 60,
		onEnter = onEnterStation,
		onExit = onExitStation,
		nearby = nearbyStation,
		pumps = pumps,
	})
end
