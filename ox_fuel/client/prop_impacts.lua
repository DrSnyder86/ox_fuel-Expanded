local impacts = {}
local lastFrame = -1
local lastHitEntity
local lastHitCoords

local function rotationToDirection(rotation)
	local pitch = math.rad(rotation.x)
	local yaw = math.rad(rotation.z)
	local horizontal = math.abs(math.cos(pitch))

	return vector3(-math.sin(yaw) * horizontal, math.cos(yaw) * horizontal, math.sin(pitch))
end

function impacts.getWeaponHit()
	local frame = GetFrameCount()

	if frame == lastFrame then return lastHitEntity, lastHitCoords end

	lastFrame = frame
	lastHitEntity = nil
	lastHitCoords = nil

	if not cache.ped or not DoesEntityExist(cache.ped) or not IsPedShooting(cache.ped) then return end

	local origin = GetGameplayCamCoord()
	local direction = rotationToDirection(GetGameplayCamRot(2))
	local destination = origin + (direction * 250.0)
	local handle = StartExpensiveSynchronousShapeTestLosProbe(
		origin.x,
		origin.y,
		origin.z,
		destination.x,
		destination.y,
		destination.z,
		511,
		cache.ped,
		7
	)
	local _, hit, endCoords, _, entity = GetShapeTestResult(handle)

	if hit == 1 then
		lastHitEntity = entity and entity ~= 0 and entity or nil
		lastHitCoords = endCoords
	end

	return lastHitEntity, lastHitCoords
end

function impacts.matchesWeaponHit(record, entity, coords, radius)
	if not record or record.destroyed or not record.damageable then return false end
	if entity and record.entity == entity then return true end
	if not coords then return false end

	return #(coords - record.coords) <= math.max(tonumber(radius) or 1.5, 0.1)
end

function impacts.vehicleWillHit(record, options)
	if not record or record.destroyed or not record.damageable then return false end

	local vehicle = cache.vehicle

	if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then return false end

	local speed = GetEntitySpeed(vehicle)
	local minimumSpeed = math.max(tonumber(options.vehicleImpactSpeed) or 6.0, 0.1)

	if speed < minimumSpeed then return false end

	local vehicleCoords = GetEntityCoords(vehicle)
	local offsetX = record.coords.x - vehicleCoords.x
	local offsetY = record.coords.y - vehicleCoords.y
	local offsetZ = record.coords.z - vehicleCoords.z
	local horizontalDistance = math.sqrt((offsetX * offsetX) + (offsetY * offsetY))
	local triggerDistance = math.max(tonumber(options.vehicleImpactDistance) or 3.0, 0.5)

	if horizontalDistance > triggerDistance or math.abs(offsetZ) > math.max(tonumber(options.vehicleImpactHeight) or 2.25, 0.5) then return false end
	if horizontalDistance <= 0.001 then return true end

	local velocity = GetEntityVelocity(vehicle)
	local horizontalSpeed = math.sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))

	if horizontalSpeed <= 0.001 then return false end

	local approach = ((velocity.x * offsetX) + (velocity.y * offsetY)) / (horizontalSpeed * horizontalDistance)

	return approach >= math.clamp(tonumber(options.vehicleApproachDot) or 0.6, -1.0, 1.0)
end

return impacts
