local utils = {}
local nozzleMounts = require 'client.nozzle_mounts'

---@param coords vector3
---@param options? table
---@return integer
function utils.createBlip(coords, options)
	options = options or {}

	local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
	SetBlipSprite(blip, options.sprite or 361)
	SetBlipDisplay(blip, options.display or 4)
	SetBlipScale(blip, options.scale or 0.5)
	SetBlipColour(blip, options.colour or 47)
	SetBlipAsShortRange(blip, options.shortRange ~= false)
	BeginTextCommandSetBlipName(options.name or 'ox_fuel_station')
	EndTextCommandSetBlipName(blip)

	return blip
end

function utils.getVehicleInFront()
	local coords = GetEntityCoords(cache.ped)
	local destination = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.2, -0.25)
	local handle = StartShapeTestCapsule(coords.x, coords.y, coords.z, destination.x, destination.y, destination.z, 2.2,
		2, cache.ped, 4)

	while true do
		Wait(0)
		local retval, _, _, _, entityHit = GetShapeTestResult(handle)

		if retval ~= 1 then
			return entityHit ~= 0 and entityHit
		end
	end
end

---@param enabled boolean?
function utils.setFuelCapDebug(enabled)
	nozzleMounts.setDebug(enabled)
end

function utils.clearFuelCapCache()
	nozzleMounts.clearCache()
end

---@param vehicle integer
function utils.getVehiclePetrolCapBoneIndex(vehicle)
	local mount = nozzleMounts.resolve(vehicle)

	return mount and mount.boneIndex ~= 0 and mount.boneIndex or nil
end

---@param vehicle integer
---@return vector3?
function utils.getVehiclePetrolCapPosition(vehicle)
	local mount = nozzleMounts.resolve(vehicle)

	return mount and mount.position or nil
end

---@param vehicle integer
---@return table?
function utils.getVehiclePetrolCapAttachment(vehicle)
	return nozzleMounts.resolve(vehicle, 'connector')
end

---@param vehicle integer
---@return table?
function utils.getVehicleFuelNozzleMount(vehicle)
	return nozzleMounts.resolve(vehicle)
end

---@param vehicle integer
---@param distance? number
---@return boolean
function utils.isNearVehiclePetrolCap(vehicle, distance)
	return nozzleMounts.isNear(vehicle, distance)
end

exports('getVehicleFuelNozzleMount', utils.getVehicleFuelNozzleMount)

---@return number
local function defaultMoneyCheck()
	return exports.ox_inventory:GetItemCount('money')
end

utils.getMoney = defaultMoneyCheck

exports('setMoneyCheck', function(fn)
	utils.getMoney = fn or defaultMoneyCheck
end)

return utils
