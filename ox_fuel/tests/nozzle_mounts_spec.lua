package.path = './?.lua;./?/init.lua;' .. package.path

local vector = {}
vector.__index = vector

function vector.__add(left, right)
	return vector3(left.x + right.x, left.y + right.y, left.z + right.z)
end

function vector.__sub(left, right)
	return vector3(left.x - right.x, left.y - right.y, left.z - right.z)
end

function vector.__mul(left, right)
	if type(left) == 'number' then left, right = right, left end

	return vector3(left.x * right, left.y * right, left.z * right)
end

function vector.__len(value)
	return math.sqrt((value.x * value.x) + (value.y * value.y) + (value.z * value.z))
end

function vector3(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, vector)
end

local hashes = {}
local nextHash = 1000

function joaat(name)
	name = name:lower()

	if not hashes[name] then
		hashes[name] = nextHash
		nextHash = nextHash + 1
	end

	return hashes[name]
end

local profiles = require 'nozzle_offsets'
local profileCount = 0

for _ in pairs(profiles) do profileCount = profileCount + 1 end

assert(profileCount == 669, ('expected 669 imported profiles, got %s'):format(profileCount))

profiles[123456] = {
	bone = 'root',
	distance = 2.4,
	nozzleOffset = { forward = 0.2, right = -0.5, up = 0.4 },
	nozzleRotation = { x = 1.0, y = 2.0, z = 3.0 },
	connectorOffset = { forward = -0.3, right = 0.6, up = 0.7 },
	connectorRotation = { x = 11.0, y = 12.0, z = 13.0 },
}

profiles[-2000000000] = {
	bone = 'root',
	distance = 1.5,
	nozzleOffset = { forward = 0.0, right = 0.0, up = 0.0 },
}

package.loaded.config = {
	nozzle = {
		fuelCapDistance = 1.8,
		vehicleAttachOffset = { x = 0.0, y = -0.03, z = 0.02 },
		vehicleAttachRotation = { x = -90.0, y = 0.0, z = 0.0 },
		mirrorRightSide = true,
		rightSideRotationZ = 180.0,
		fuelCapFallback = {
			enabled = true,
			attach = true,
			sidePadding = 0.18,
			heightScale = 0.48,
			rearQuarterScale = 0.25,
			middleScale = 0.48,
		},
		offsetDebug = { enabled = false },
	},
}

cache = { ped = 99 }
lib = {}

local vehicles = {}
local boneSearches = {}

local function addVehicle(entity, model, bones, positions)
	vehicles[entity] = {
		model = model,
		bones = bones or {},
		positions = positions or {},
		coords = vector3(0.0, 0.0, 0.0),
	}
end

function DoesEntityExist(entity) return entity == cache.ped or vehicles[entity] ~= nil end
function GetEntityType(entity) return vehicles[entity] and 2 or 1 end
function GetEntityModel(entity) return vehicles[entity].model end
function GetEntityCoords(entity) return vehicles[entity] and vehicles[entity].coords or vector3(-2.0, 0.0, 0.0) end
function GetEntityBoneIndexByName(entity, name)
	boneSearches[entity] = (boneSearches[entity] or 0) + 1

	return vehicles[entity].bones[name] or -1
end
function GetWorldPositionOfEntityBone(entity, index) return vehicles[entity].positions[index] end
function GetModelDimensions() return vector3(-1.0, -2.0, 0.0), vector3(1.0, 2.0, 1.0) end
function GetEntityMatrix()
	return vector3(0.0, 1.0, 0.0), vector3(1.0, 0.0, 0.0), vector3(0.0, 0.0, 1.0), vector3(0.0, 0.0, 0.0)
end
function GetEntityRotation() return vector3(0.0, 0.0, 0.0) end
function GetOffsetFromEntityInWorldCoords(entity, x, y, z) return vehicles[entity].coords + vector3(x, y, z) end
function GetOffsetFromEntityGivenWorldCoords(_, x, y, z) return vector3(x, y, z) end
function GetDisplayNameFromVehicleModel(model) return ('MODEL_%s'):format(model) end
function RegisterCommand() end
function AddEventHandler() end
function CreateThread() end
function GetCurrentResourceName() return 'ox_fuel' end

local mounts = require 'client.nozzle_mounts'

addVehicle(1, joaat('adder'), { wheel_lr = 7 }, { [7] = vector3(-1.0, -1.0, 0.5) })
local imported = mounts.resolve(1)
assert(imported.source == 'override', 'imported profile did not take priority')
assert(imported.boneName == 'wheel_lr', 'explicit profile did not retain LC Fuel bone fallback')
assert(imported.rotationOrder == 2 and imported.syncRot == false, 'LC Fuel attachment semantics were not retained')

addVehicle(2, joaat('futurecar'), { petrolcap = 8 }, { [8] = vector3(1.0, -1.0, 0.5) })
local automatic = mounts.resolve(2)
assert(automatic.source == 'bone' and automatic.boneName == 'petrolcap', 'automatic petrolcap lookup failed')
assert(automatic.side == 'right' and automatic.rotation.z == 180.0, 'right-side automatic rotation failed')
local searches = boneSearches[2]
mounts.resolve(2)
assert(boneSearches[2] == searches, 'bone detection was repeated for a cached model')

addVehicle(3, joaat('unsafeonly'), { wheel_lr = 9 }, { [9] = vector3(-1.0, -1.0, 0.5) })
local fallback = mounts.resolve(3)
assert(fallback.source == 'fallback' and fallback.boneName == nil, 'unsafe bone was selected automatically')

addVehicle(4, 123456)
local numeric = mounts.resolve(4)
assert(numeric.source == 'override' and numeric.boneName == 'root', 'numeric hash/root profile failed')
assert(numeric.distance == 2.4, 'profile interaction distance was not preserved')
local numericConnector = mounts.resolve(4, 'connector')
assert(numericConnector.offset.x == 0.6 and numericConnector.offset.y == -0.3 and numericConnector.offset.z == 0.7,
	'connector-specific offset was not selected')
assert(numericConnector.rotation.x == -34.0 and numericConnector.rotation.y == 12.0 and numericConnector.rotation.z == -77.0,
	'connector-specific rotation was not selected')
assert(numeric.offset.x == -0.5 and numeric.offset.y == 0.2 and numeric.offset.z == 0.4,
	'connector profile changed the gas-nozzle offset')

addVehicle(5, 2294967296)
local unsigned = mounts.resolve(5)
assert(unsigned.source == 'override' and unsigned.distance == 1.5, 'signed/unsigned hash alias failed')

addVehicle(6, joaat('caddy'), { petrolcap = 10 }, { [10] = vector3(-0.8, -1.0, 0.5) })
local caddy = mounts.resolve(6)
assert(caddy.source == 'override', 'caddy did not use its imported LC Fuel profile')
assert(caddy.rotation.x == -45.0 and caddy.rotation.z == -90.0, 'caddy LC Fuel mount rotation changed')
local caddyConnector = mounts.resolve(6, 'connector')
assert(caddyConnector.offset.x == 0.0 and caddyConnector.offset.y == -0.05 and caddyConnector.offset.z == 0.53,
	'caddy connector-specific offset was not selected')
assert(caddyConnector.rotation.x == 20.0 and caddyConnector.rotation.y == -45.0 and caddyConnector.rotation.z == -90.0,
	'caddy connector-specific rotation was not selected')

print('nozzle_mounts_spec.lua OK')
