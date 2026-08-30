local config = require 'config'
local settings = config and config.versionCheck

if not settings or settings == false then return end

if settings == true then
	settings = {}
elseif type(settings) ~= 'table' or settings.enabled == false then
	return
end

local resourceName = GetCurrentResourceName()
local currentVersion = GetResourceMetadata(resourceName, 'version', 0)
local manifestUrl = settings.manifestUrl or 'https://raw.githubusercontent.com/DrSnyder86/ox_fuel-Expanded/main/ox_fuel/fxmanifest.lua'
local downloadUrl = settings.downloadUrl or 'https://github.com/DrSnyder86/ox_fuel-Expanded'

local function log(message)
	print(('[%s] %s'):format(resourceName, message))
end

local function getVersionParts(version)
	if type(version) ~= 'string' then return end

	local parts = {}

	for value in version:gmatch('%d+') do
		parts[#parts + 1] = tonumber(value)
	end

	return #parts > 0 and parts or nil
end

local function compareVersions(installed, available)
	local installedParts = getVersionParts(installed)
	local availableParts = getVersionParts(available)

	if not installedParts or not availableParts then return end

	for index = 1, math.max(#installedParts, #availableParts) do
		local installedPart = installedParts[index] or 0
		local availablePart = availableParts[index] or 0

		if installedPart < availablePart then return -1 end
		if installedPart > availablePart then return 1 end
	end

	return 0
end

local function getManifestVersion(manifest)
	if type(manifest) ~= 'string' then return end

	for line in manifest:gmatch('[^\r\n]+') do
		local version = line:match('^%s*version%s+[\'\"]([^\'\"]+)[\'\"]')

		if version then return version end
	end
end

CreateThread(function()
	Wait(math.max(tonumber(settings.delayMs) or 1500, 0))

	PerformHttpRequest(manifestUrl, function(statusCode, response)
		if statusCode ~= 200 then
			if settings.verboseErrors then
				log(('Version check failed (HTTP %s).'):format(statusCode or 'unknown'))
			end

			return
		end

		local availableVersion = getManifestVersion(response)
		local comparison = compareVersions(currentVersion, availableVersion)

		if not comparison then
			if settings.verboseErrors then
				log('Version check failed because a manifest version could not be read.')
			end

			return
		end

		if comparison < 0 then
			log(('Update available: %s (installed: %s)'):format(availableVersion, currentVersion))
			log(('Download: %s'):format(downloadUrl))
		elseif settings.notifyCurrent then
			local status = comparison == 0 and 'is current' or 'is newer than the public package'

			log(('Version %s %s.'):format(currentVersion, status))
		end
	end, 'GET', '', {
		['Cache-Control'] = 'no-cache',
		['User-Agent'] = 'ox_fuel Expanded version checker',
	})
end)
