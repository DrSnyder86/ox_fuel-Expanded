local config = require 'config'
local configuredProfiles = require 'nozzle_offsets'

local settings = config.nozzle or {}
local electricSettings = config.electric or {}
local fallbackSettings = settings.fuelCapFallback or {}
local debugSettings = settings.offsetDebug or {}
local mounts = {}

local safeBoneGroups = {
	{ 'petrolcap', 'petrolcap ' },
	{ 'petroltank' },
	{ 'petroltank_l', 'petroltank_r' },
}

local explicitOverrideBones = {
	'petrolcap',
	'petrolcap ',
	'petroltank',
	'petroltank_l',
	'petroltank_r',
	'wheel_lr',
	'wheel_lf',
	'engine',
	'chassis_dummy',
}

local profileCache = {}
local modelCache = {}
local missingModels = {}
local debugEnabled = settings.fuelCapDebug == true
local debugEditor

local function number(value, fallback)
	value = tonumber(value)

	return value ~= nil and value or fallback
end

local function copyOffset(offset)
	offset = type(offset) == 'table' and offset or {}

	return {
		forward = number(offset.forward, 0.0),
		right = number(offset.right, 0.0),
		up = number(offset.up, 0.0),
	}
end

local function copyRotation(rotation)
	rotation = type(rotation) == 'table' and rotation or {}

	return {
		x = number(rotation.x, 0.0),
		y = number(rotation.y, 0.0),
		z = number(rotation.z, 0.0),
	}
end

local function normalizeProfile(profile, modelName)
	if type(profile) ~= 'table' or type(profile.nozzleOffset) ~= 'table' then return end

	return {
		modelName = modelName,
		bone = type(profile.bone) == 'string' and profile.bone or nil,
		distance = math.max(number(profile.distance, settings.fuelCapDistance or 1.8), 0.1),
		nozzleOffset = copyOffset(profile.nozzleOffset),
		nozzleRotation = copyRotation(profile.nozzleRotation),
		connectorOffset = type(profile.connectorOffset) == 'table' and copyOffset(profile.connectorOffset) or nil,
		connectorRotation = type(profile.connectorRotation) == 'table' and copyRotation(profile.connectorRotation) or nil,
	}
end

for key, profile in pairs(configuredProfiles) do
	local model
	local modelName

	if type(key) == 'number' then
		model = key
	elseif type(key) == 'string' and key ~= '' then
		modelName = key:lower()
		model = joaat(modelName)
	end

	local normalized = model and normalizeProfile(profile, modelName)

	if normalized then
		profileCache[model] = normalized

		-- Accept either signed or unsigned decimal forms of the same 32-bit model hash.
		if model < 0 then
			profileCache[model + 4294967296] = normalized
		elseif model > 2147483647 then
			profileCache[model - 4294967296] = normalized
		end
	end
end

local function spawnNameForVehicle(vehicle)
	if type(GetEntityArchetypeName) == 'function' then
		local ok, name = pcall(GetEntityArchetypeName, vehicle)

		if ok and type(name) == 'string' and name ~= '' then
			return name:lower()
		end
	end
end

local function modelLabelForVehicle(vehicle, model)
	local spawnName = spawnNameForVehicle(vehicle)

	if spawnName then return spawnName end

	local displayName = GetDisplayNameFromVehicleModel(model)

	if displayName and displayName ~= '' and displayName ~= 'CARNOTFOUND' and displayName ~= 'NULL' then
		return displayName:lower()
	end
end

local function findBones(vehicle, names)
	local bones = {}

	for i = 1, #names do
		local boneIndex = GetEntityBoneIndexByName(vehicle, names[i])

		if boneIndex ~= -1 then
			bones[#bones + 1] = {
				name = names[i],
				index = boneIndex,
			}
		end
	end

	return bones
end

local function firstValidBone(vehicle, names)
	for i = 1, #names do
		if names[i] == 'root' then
			return { name = 'root', index = 0, root = true }
		end

		local boneIndex = GetEntityBoneIndexByName(vehicle, names[i])

		if boneIndex ~= -1 then
			return { name = names[i], index = boneIndex }
		end
	end
end

local function buildModelTemplate(vehicle, model)
	local profile = profileCache[model]
	local template = { profile = profile }

	if profile then
		if profile.bone then
			template.overrideBone = firstValidBone(vehicle, { profile.bone })
			template.invalidOverrideBone = not template.overrideBone
		else
			template.overrideBone = firstValidBone(vehicle, explicitOverrideBones)
		end

		if template.overrideBone then return template end
	end

	for i = 1, #safeBoneGroups do
		local bones = findBones(vehicle, safeBoneGroups[i])

		if #bones > 0 then
			template.safeBones = bones
			return template
		end
	end

	template.missingSafeBones = true

	if fallbackSettings.enabled ~= false then
		local minDim, maxDim = GetModelDimensions(model)

		if minDim and maxDim then
			local length = maxDim.y - minDim.y
			local height = maxDim.z - minDim.z
			local sidePadding = number(fallbackSettings.sidePadding, 0.18)
			local capHeight = minDim.z + (height * number(fallbackSettings.heightScale, 0.48))
			local rearQuarter = minDim.y + (length * number(fallbackSettings.rearQuarterScale, 0.25))
			local middle = minDim.y + (length * number(fallbackSettings.middleScale, 0.48))

			template.fallbackOffsets = {
				{ x = minDim.x - sidePadding, y = rearQuarter, z = capHeight },
				{ x = minDim.x - sidePadding, y = middle, z = capHeight },
				{ x = maxDim.x + sidePadding, y = rearQuarter, z = capHeight },
				{ x = maxDim.x + sidePadding, y = middle, z = capHeight },
			}
		end
	end

	return template
end

local function getModelTemplate(vehicle)
	local model = GetEntityModel(vehicle)
	local template = modelCache[model]

	if not template then
		template = buildModelTemplate(vehicle, model)
		modelCache[model] = template
	end

	return template, model
end

local function nearestEntry(entries, positionForEntry)
	local pedCoords = GetEntityCoords(cache.ped)
	local nearest
	local nearestPosition
	local nearestDistance

	for i = 1, #entries do
		local position = positionForEntry(entries[i])

		if position then
			local distance = #(pedCoords - position)

			if not nearestDistance or distance < nearestDistance then
				nearest = entries[i]
				nearestPosition = position
				nearestDistance = distance
			end
		end
	end

	return nearest, nearestPosition, nearestDistance
end

local function vectorFromTable(value, defaults)
	value = type(value) == 'table' and value or {}
	defaults = defaults or {}

	return vector3(
		number(value.x or value[1], number(defaults.x, 0.0)),
		number(value.y or value[2], number(defaults.y, 0.0)),
		number(value.z or value[3], number(defaults.z, 0.0))
	)
end

local function automaticRotation(rightSide)
	local rotation = vectorFromTable(settings.vehicleAttachRotation, { x = -90.0, y = 0.0, z = 0.0 })

	if rightSide and settings.mirrorRightSide ~= false then
		rotation = vector3(rotation.x, rotation.y, rotation.z + number(settings.rightSideRotationZ, 180.0))
	end

	return rotation
end

local function worldAdjustment(vehicle, offset)
	local forwardVector, rightVector, upVector = GetEntityMatrix(vehicle)

	return (rightVector * offset.x) + (forwardVector * offset.y) + (upVector * offset.z)
end

local function buildAutomaticBoneMount(vehicle, bone)
	local offset = vectorFromTable(settings.vehicleAttachOffset, { x = 0.0, y = -0.03, z = 0.02 })
	local bonePosition = bone.root and GetEntityCoords(vehicle) or GetWorldPositionOfEntityBone(vehicle, bone.index)
	local localPosition = GetOffsetFromEntityGivenWorldCoords(vehicle, bonePosition.x, bonePosition.y, bonePosition.z)
	local rightSide = localPosition.x > 0.0

	return {
		boneIndex = bone.index,
		boneName = bone.name,
		offset = offset,
		rotation = automaticRotation(rightSide),
		distance = settings.fuelCapDistance or 1.8,
		position = bonePosition + worldAdjustment(vehicle, offset),
		source = 'bone',
		side = rightSide and 'right' or 'left',
		canAttach = true,
	}
end

local function buildProfileMount(vehicle, profile, bone, attachmentType)
	if not profile or not bone then return end

	local vehicleRotation = GetEntityRotation(vehicle)
	local forwardVector, rightVector, upVector = GetEntityMatrix(vehicle)
	local useConnector = attachmentType == 'connector'
	local offset = useConnector and profile.connectorOffset or profile.nozzleOffset
	local rotation = useConnector and profile.connectorRotation or profile.nozzleRotation

	offset = offset or profile.nozzleOffset
	rotation = rotation or profile.nozzleRotation
	local finalOffset = (forwardVector * offset.forward) + (rightVector * offset.right) + (upVector * offset.up)
	local bonePosition = bone.root and GetEntityCoords(vehicle) or GetWorldPositionOfEntityBone(vehicle, bone.index)

	return {
		boneIndex = bone.index,
		boneName = bone.name,
		offset = finalOffset,
		rotation = vector3(
			vehicleRotation.x + rotation.x - 45.0,
			vehicleRotation.y + rotation.y,
			vehicleRotation.z + rotation.z - 90.0
		),
		distance = profile.distance,
		position = bonePosition + finalOffset,
		source = 'override',
		canAttach = true,
		useSoftPinning = false,
		rotationOrder = 2,
		syncRot = false,
		profile = profile,
	}
end

local function configuredPositionMount(vehicle, model)
	local configured = settings.fuelCapOffsets and settings.fuelCapOffsets[model]

	if type(configured) ~= 'table' then return end

	local entries = {}

	if configured.x or configured[1] and type(configured[1]) == 'number' then
		entries[1] = configured
	else
		for i = 1, #configured do
			if type(configured[i]) == 'table' then entries[#entries + 1] = configured[i] end
		end
	end

	local entry, position = nearestEntry(entries, function(offset)
		local localOffset = vectorFromTable(offset)

		return GetOffsetFromEntityInWorldCoords(vehicle, localOffset.x, localOffset.y, localOffset.z)
	end)

	if not entry then return end

	return {
		boneIndex = 0,
		boneName = nil,
		offset = vectorFromTable(entry),
		rotation = automaticRotation(number(entry.x or entry[1], 0.0) > 0.0),
		distance = number(entry.distance, settings.fuelCapDistance or 1.8),
		position = position,
		source = 'override',
		side = number(entry.x or entry[1], 0.0) > 0.0 and 'right' or 'left',
		canAttach = true,
	}
end

local function buildFallbackMount(vehicle, offsets)
	if not offsets or #offsets == 0 then return end

	local entry, position = nearestEntry(offsets, function(offset)
		return GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
	end)

	if not entry then return end

	return {
		boneIndex = 0,
		boneName = nil,
		offset = vector3(entry.x, entry.y, entry.z),
		rotation = automaticRotation(entry.x > 0.0),
		distance = settings.fuelCapDistance or 1.8,
		position = position,
		source = 'fallback',
		side = entry.x > 0.0 and 'right' or 'left',
		canAttach = fallbackSettings.attach ~= false,
	}
end

local function reportMissingModel(vehicle, model, template)
	if not debugEnabled
		or debugSettings.reportMissing == false
		or template.profile
		or not template.missingSafeBones
		or missingModels[model]
	then return end

	missingModels[model] = true
	local name = modelLabelForVehicle(vehicle, model)

	print(('^3[ox_fuel] No nozzle override or safe fuel bone for %s (hash %s). Using %s.^0'):format(
		name or 'unknown vehicle',
		model,
		template.fallbackOffsets and 'the body fallback' or 'manual configuration'
	))
end

---@param vehicle integer
---@return table?
function mounts.resolve(vehicle, attachmentType)
	if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end

	local template, model = getModelTemplate(vehicle)
	local positionOverride = configuredPositionMount(vehicle, model)

	if positionOverride then return positionOverride end

	if template.profile and template.overrideBone then
		return buildProfileMount(vehicle, template.profile, template.overrideBone, attachmentType)
	end

	if template.safeBones then
		local bone = template.safeBones[1]

		if #template.safeBones > 1 then
			bone = nearestEntry(template.safeBones, function(candidate)
				return GetWorldPositionOfEntityBone(vehicle, candidate.index)
			end)
		end

		return buildAutomaticBoneMount(vehicle, bone)
	end

	reportMissingModel(vehicle, model, template)

	return buildFallbackMount(vehicle, template.fallbackOffsets)
end

function mounts.isNear(vehicle, distance)
	local mount = mounts.resolve(vehicle)

	if not mount or not mount.position then return false end

	local defaultDistance = settings.fuelCapDistance or 1.8
	local maximumDistance = mount.distance or defaultDistance

	if distance then
		maximumDistance = math.max(maximumDistance + (distance - defaultDistance), 0.1)
	end

	return #(GetEntityCoords(cache.ped) - mount.position) <= maximumDistance
end

function mounts.clearCache()
	modelCache = {}
	missingModels = {}
end

local function markerColor(source)
	if source == 'override' then return 80, 180, 255 end
	if source == 'bone' then return 80, 255, 120 end

	return 255, 210, 80
end

local function drawMountMarker(mount, scale)
	if not mount or not mount.position then return end

	local red, green, blue = markerColor(mount.source)

	DrawMarker(
		28,
		mount.position.x, mount.position.y, mount.position.z,
		0.0, 0.0, 0.0,
		0.0, 0.0, 0.0,
		scale, scale, scale,
		red, green, blue, 220,
		false, false, 2, false, nil, nil, false
	)
end

local function startDebugMarkerThread()
	CreateThread(function()
		while true do
			if debugEnabled then
				local pedCoords = GetEntityCoords(cache.ped)
				local maximumDistance = number(settings.fuelCapDebugDistance, 15.0)
				local vehicles = GetGamePool('CVehicle')

				for i = 1, #vehicles do
					local vehicle = vehicles[i]

					if DoesEntityExist(vehicle) and #(GetEntityCoords(vehicle) - pedCoords) <= maximumDistance then
						drawMountMarker(mounts.resolve(vehicle), 0.10)
					end
				end

				Wait(0)
			else
				Wait(1000)
			end
		end
	end)
end

local function rotationToDirection(rotation)
	local adjustedX = math.rad(rotation.x)
	local adjustedZ = math.rad(rotation.z)
	local cosine = math.abs(math.cos(adjustedX))

	return vector3(-math.sin(adjustedZ) * cosine, math.cos(adjustedZ) * cosine, math.sin(adjustedX))
end

local function getLookedAtVehicle()
	local origin = GetGameplayCamCoord()
	local destination = origin + (rotationToDirection(GetGameplayCamRot(2)) * number(debugSettings.raycastDistance, 20.0))
	local handle = StartShapeTestRay(origin.x, origin.y, origin.z, destination.x, destination.y, destination.z, 2, cache.ped, 0)

	while true do
		Wait(0)
		local result, hit, hitPosition, _, entity = GetShapeTestResult(handle)

		if result ~= 1 then
			if hit and hit ~= 0 and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2 then
				return entity, hitPosition
			end

			return
		end
	end
end

local function offsetFromWorldPoint(vehicle, origin, position)
	local forwardVector, rightVector, upVector = GetEntityMatrix(vehicle)
	local direction = position - origin

	return {
		forward = (direction.x * forwardVector.x) + (direction.y * forwardVector.y) + (direction.z * forwardVector.z),
		right = (direction.x * rightVector.x) + (direction.y * rightVector.y) + (direction.z * rightVector.z),
		up = (direction.x * upVector.x) + (direction.y * upVector.y) + (direction.z * upVector.z),
	}
end

local function editorProfileForVehicle(vehicle, hitPosition, attachmentType)
	local model = GetEntityModel(vehicle)
	local existing = profileCache[model]
	local profile

	if existing then
		local resolved = mounts.resolve(vehicle, attachmentType)
		local explicitBone = existing.bone and firstValidBone(vehicle, { existing.bone })

		profile = {
			bone = explicitBone and existing.bone or resolved and resolved.boneName or 'root',
			distance = existing.distance,
			nozzleOffset = copyOffset(existing.nozzleOffset),
			nozzleRotation = copyRotation(existing.nozzleRotation),
			connectorOffset = existing.connectorOffset and copyOffset(existing.connectorOffset) or nil,
			connectorRotation = existing.connectorRotation and copyRotation(existing.connectorRotation) or nil,
			hasConnectorOverride = existing.connectorOffset ~= nil or existing.connectorRotation ~= nil,
		}
	else
		local mount = mounts.resolve(vehicle)
		local boneName = mount and mount.boneName or 'root'
		local bonePosition = mount and mount.boneIndex and mount.boneIndex ~= 0
			and GetWorldPositionOfEntityBone(vehicle, mount.boneIndex)
			or GetEntityCoords(vehicle)
		local nozzleOffset = hitPosition and offsetFromWorldPoint(vehicle, bonePosition, hitPosition)
			or { forward = 0.0, right = 0.0, up = 0.0 }
		local rightSide = hitPosition
			and GetOffsetFromEntityGivenWorldCoords(vehicle, hitPosition.x, hitPosition.y, hitPosition.z).x > 0.0

		profile = {
			bone = boneName,
			distance = settings.fuelCapDistance or 1.8,
			nozzleOffset = nozzleOffset,
			nozzleRotation = {
				x = 0.0,
				y = 0.0,
				z = rightSide and number(settings.rightSideRotationZ, 180.0) or 0.0,
			},
		}
	end

	if attachmentType == 'connector' then
		profile.connectorOffset = profile.connectorOffset or copyOffset(profile.nozzleOffset)
		profile.connectorRotation = profile.connectorRotation or copyRotation(profile.nozzleRotation)
		profile.hasConnectorOverride = true
	end

	return profile
end

local function boneOptions(vehicle)
	local options = {}
	local seen = {}

	for i = 1, #explicitOverrideBones do
		local name = explicitOverrideBones[i]
		local boneIndex = GetEntityBoneIndexByName(vehicle, name)

		if boneIndex ~= -1 and not seen[name] then
			seen[name] = true
			options[#options + 1] = { value = name, label = name }
		end
	end

	options[#options + 1] = { value = 'root', label = 'root (vehicle origin)' }

	return options
end

local debugMenuId = 'ox_fuel_mount_offset_editor'
local attachDebugPreview

local function scrollValues(minimum, maximum, step, precision)
	local values = {}
	local count = math.floor(((maximum - minimum) / step) + 0.5)
	local format = ('%%.%sf'):format(precision)

	for i = 0, count do values[#values + 1] = format:format(minimum + (i * step)) end

	return values
end

local function scrollIndex(value, minimum, step, count)
	return math.clamp(math.floor(((number(value, minimum) - minimum) / step) + 0.5) + 1, 1, count)
end

local function editDebugProfile(editor)
	local vehicle = editor.vehicle
	local profile = editor.profile
	local options = boneOptions(vehicle)
	local useConnector = editor.attachmentType == 'connector'
	local offsetKey = useConnector and 'connectorOffset' or 'nozzleOffset'
	local rotationKey = useConnector and 'connectorRotation' or 'nozzleRotation'
	local offset = profile[offsetKey] or copyOffset(profile.nozzleOffset)
	local rotation = profile[rotationKey] or copyRotation(profile.nozzleRotation)

	if #options == 0 then return end
	if not profile.bone or profile.bone ~= 'root' and GetEntityBoneIndexByName(vehicle, profile.bone) == -1 then
		profile.bone = options[1].value
	end

	profile[offsetKey] = offset
	profile[rotationKey] = rotation
	if useConnector then profile.hasConnectorOverride = true end

	local boneValues = {}
	local boneIndex = 1

	for i = 1, #options do
		boneValues[i] = options[i].label
		if options[i].value == profile.bone then boneIndex = i end
	end

	local distanceValues = scrollValues(0.1, 5.0, 0.1, 2)
	local offsetValues = scrollValues(-5.0, 5.0, 0.01, 3)
	local rotationValues = scrollValues(-360.0, 360.0, 1.0, 0)
	local menuOptions = {
		{ label = locale('nozzle_debug_bone'), values = boneValues, defaultIndex = boneIndex, args = { kind = 'bone' }, close = false },
		{ label = locale('nozzle_debug_distance'), values = distanceValues, defaultIndex = scrollIndex(profile.distance, 0.1, 0.1, #distanceValues), args = { kind = 'distance', minimum = 0.1, step = 0.1 }, close = false },
		{ label = locale('nozzle_debug_forward'), values = offsetValues, defaultIndex = scrollIndex(offset.forward, -5.0, 0.01, #offsetValues), args = { kind = 'offset', key = 'forward', minimum = -5.0, step = 0.01 }, close = false },
		{ label = locale('nozzle_debug_right'), values = offsetValues, defaultIndex = scrollIndex(offset.right, -5.0, 0.01, #offsetValues), args = { kind = 'offset', key = 'right', minimum = -5.0, step = 0.01 }, close = false },
		{ label = locale('nozzle_debug_up'), values = offsetValues, defaultIndex = scrollIndex(offset.up, -5.0, 0.01, #offsetValues), args = { kind = 'offset', key = 'up', minimum = -5.0, step = 0.01 }, close = false },
		{ label = locale('nozzle_debug_rotation_x'), values = rotationValues, defaultIndex = scrollIndex(rotation.x, -360.0, 1.0, #rotationValues), args = { kind = 'rotation', key = 'x', minimum = -360.0, step = 1.0 }, close = false },
		{ label = locale('nozzle_debug_rotation_y'), values = rotationValues, defaultIndex = scrollIndex(rotation.y, -360.0, 1.0, #rotationValues), args = { kind = 'rotation', key = 'y', minimum = -360.0, step = 1.0 }, close = false },
		{ label = locale('nozzle_debug_rotation_z'), values = rotationValues, defaultIndex = scrollIndex(rotation.z, -360.0, 1.0, #rotationValues), args = { kind = 'rotation', key = 'z', minimum = -360.0, step = 1.0 }, close = false },
	}

	local function applyValue(_, selectedIndex, args)
		if not selectedIndex or debugEditor ~= editor or not DoesEntityExist(editor.preview) then return end

		if args.kind == 'bone' then
			profile.bone = options[selectedIndex].value
		else
			local value = args.minimum + ((selectedIndex - 1) * args.step)

			if args.kind == 'distance' then
				profile.distance = value
			elseif args.kind == 'offset' then
				offset[args.key] = value
			else
				rotation[args.key] = value
			end
		end

		attachDebugPreview(editor)
	end

	editor.editing = true
	lib.registerMenu({
		id = debugMenuId,
		title = locale(useConnector and 'connector_debug_title' or 'nozzle_debug_title'),
		position = 'top-right',
		canClose = true,
		disableInput = false,
		options = menuOptions,
		onSideScroll = applyValue,
		onClose = function()
			if debugEditor == editor then editor.editing = false end
		end,
	}, applyValue)
	lib.showMenu(debugMenuId)
end

local function debugMount(vehicle, profile, attachmentType)
	local bone = profile.bone and firstValidBone(vehicle, { profile.bone })

	return buildProfileMount(vehicle, profile, bone, attachmentType)
end

local function copiedProfile(vehicle, profile)
	local model = GetEntityModel(vehicle)
	local name = spawnNameForVehicle(vehicle)
	local key = name and ("['%s']"):format(name) or ('[%s]'):format(model)
	local output = ([=[%s = {
	distance = %.2f,
	bone = '%s',
	nozzleOffset = {
		forward = %.3f,
		right = %.3f,
		up = %.3f,
	},
	nozzleRotation = {
		x = %.2f,
		y = %.2f,
		z = %.2f,
	},]=]):format(
		key,
		profile.distance,
		profile.bone,
		profile.nozzleOffset.forward,
		profile.nozzleOffset.right,
		profile.nozzleOffset.up,
		profile.nozzleRotation.x,
		profile.nozzleRotation.y,
		profile.nozzleRotation.z
	)

	if profile.hasConnectorOverride then
		output = output .. ([=[
	connectorOffset = {
		forward = %.3f,
		right = %.3f,
		up = %.3f,
	},
	connectorRotation = {
		x = %.2f,
		y = %.2f,
		z = %.2f,
	},]=]):format(
			profile.connectorOffset.forward,
			profile.connectorOffset.right,
			profile.connectorOffset.up,
			profile.connectorRotation.x,
			profile.connectorRotation.y,
			profile.connectorRotation.z
		)
	end

	return output .. '\n},'
end

local function deleteDebugPreview(editor)
	local preview = editor and editor.preview

	if preview and DoesEntityExist(preview) then
		DetachEntity(preview, true, true)
		DeleteEntity(preview)
	end

	if editor then editor.preview = nil end
end

local function previewMount(editor)
	local mount = debugMount(editor.vehicle, editor.profile, editor.attachmentType)

	if not mount then return end

	if editor.attachmentType == 'connector' then
		local offset = vectorFromTable(electricSettings.vehicleAttachOffset)
		local correction = vectorFromTable(electricSettings.vehicleAttachRotation)

		mount.offset = mount.offset + offset
		mount.rotation = mount.rotation + correction
	end

	return mount
end

attachDebugPreview = function(editor)
	if not editor.preview or not DoesEntityExist(editor.preview) then return false end

	local mount = previewMount(editor)

	if not mount then return false end

	DetachEntity(editor.preview, true, true)
	AttachEntityToEntity(
		editor.preview,
		editor.vehicle,
		mount.boneIndex or 0,
		mount.offset.x, mount.offset.y, mount.offset.z,
		mount.rotation.x, mount.rotation.y, mount.rotation.z,
		false,
		mount.useSoftPinning ~= false,
		false,
		false,
		mount.rotationOrder or 0,
		mount.syncRot ~= false
	)

	return true
end

local function createDebugPreview(editor)
	local model = editor.attachmentType == 'connector' and electricSettings.connectorModel or settings.model

	if not model or not IsModelInCdimage(model) or not IsModelValid(model) then return false end

	lib.requestModel(model)

	local coords = GetEntityCoords(editor.vehicle)
	local preview = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)

	SetModelAsNoLongerNeeded(model)

	if preview == 0 then return false end

	SetEntityAsMissionEntity(preview, true, true)
	SetEntityCollision(preview, false, false)
	SetEntityInvincible(preview, true)
	editor.preview = preview

	return attachDebugPreview(editor)
end

local function stopDebugEditor()
	local editor = debugEditor

	debugEditor = nil

	if editor and editor.editing and lib.getOpenMenu() == debugMenuId then lib.hideMenu(false) end

	deleteDebugPreview(editor)
	lib.hideTextUI()
end

local function startDebugEditor(vehicle, profile, attachmentType)
	local editor = {
		vehicle = vehicle,
		profile = profile,
		attachmentType = attachmentType,
		editing = false,
	}

	debugEditor = editor

	if not createDebugPreview(editor) then
		stopDebugEditor()
		return lib.notify({ type = 'error', description = locale('nozzle_debug_preview_failed') })
	end

	lib.showTextUI(locale(attachmentType == 'connector' and 'connector_debug_controls' or 'nozzle_debug_controls'), {
		icon = 'screwdriver-wrench',
	})

	CreateThread(function()
		while debugEditor == editor and DoesEntityExist(vehicle) and DoesEntityExist(editor.preview) do
			drawMountMarker(previewMount(editor), number(debugSettings.markerScale, 0.14))

			if not editor.editing and IsControlJustPressed(0, 38) then
				local output = copiedProfile(vehicle, profile)
				lib.setClipboard(output)
				print(('[ox_fuel] %s mount profile for %s (hash %s):\n%s'):format(
					attachmentType == 'connector' and 'Electric connector' or 'Fuel nozzle',
					spawnNameForVehicle(vehicle) or 'unknown vehicle',
					GetEntityModel(vehicle),
					output
				))
				lib.notify({ type = 'success', description = locale(attachmentType == 'connector' and 'connector_debug_copied' or 'nozzle_debug_copied') })
			elseif IsControlJustPressed(0, 47) and not editor.editing then
				editDebugProfile(editor)
				Wait(200)
			elseif not editor.editing and IsControlJustPressed(0, 177) then
				break
			end

			Wait(0)
		end

		if debugEditor == editor then stopDebugEditor() end
	end)
end

local function openOffsetEditor(attachmentType)
	if debugSettings.enabled ~= true then
		return lib.notify({ type = 'error', description = locale('nozzle_debug_generator_disabled') })
	end

	if debugEditor then return stopDebugEditor() end

	local vehicle, hitPosition = getLookedAtVehicle()

	if not vehicle then
		return lib.notify({ type = 'error', description = locale(attachmentType == 'connector' and 'connector_debug_no_vehicle' or 'nozzle_debug_no_vehicle') })
	end

	local profile = editorProfileForVehicle(vehicle, hitPosition, attachmentType)

	startDebugEditor(vehicle, profile, attachmentType)
end

RegisterCommand('ox_fuel_debugcaps', function()
	debugEnabled = not debugEnabled

	lib.notify({
		type = 'inform',
		description = locale(debugEnabled and 'nozzle_debug_enabled' or 'nozzle_debug_disabled'),
	})
end, false)

RegisterCommand(debugSettings.command or 'ox_fuel_nozzleoffset', function()
	openOffsetEditor('nozzle')
end, false)

RegisterCommand(debugSettings.connectorCommand or 'ox_fuel_chargeroffset', function()
	openOffsetEditor('connector')
end, false)

function mounts.setDebug(enabled)
	debugEnabled = enabled == nil and not debugEnabled or enabled == true
end

AddEventHandler('onClientResourceStop', function(resource)
	if resource == GetCurrentResourceName() and debugEditor then stopDebugEditor() end
end)

startDebugMarkerThread()

return mounts
