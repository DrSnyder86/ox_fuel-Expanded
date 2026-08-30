package.path = './?.lua;./?/init.lua;' .. package.path

local settings = {
	enabled = true,
	manifestUrl = 'https://example.test/fxmanifest.lua',
	downloadUrl = 'https://example.test/download',
	notifyCurrent = false,
	verboseErrors = true,
	delayMs = 0,
}

package.preload.config = function()
	return { versionCheck = settings }
end

local remoteManifest
local messages = {}
local originalPrint = print

function GetCurrentResourceName()
	return 'ox_fuel'
end

function GetResourceMetadata(_, key)
	return key == 'version' and '1.5.2-expanded.2' or nil
end

function CreateThread(callback)
	callback()
end

function Wait(delay)
	assert(delay == 0, 'configured startup delay was not used')
end

function PerformHttpRequest(url, callback, method, body, headers)
	assert(url == settings.manifestUrl, 'configured manifest URL was not used')
	assert(method == 'GET' and body == '', 'unexpected HTTP request options')
	assert(headers['Cache-Control'] == 'no-cache', 'version request should bypass caches')
	callback(200, remoteManifest)
end

print = function(message)
	messages[#messages + 1] = message
end

remoteManifest = [[
fx_version 'cerulean'
version '1.5.2-expanded.3'
]]

dofile('server/version.lua')

assert(#messages == 2, 'new version did not print the update and download notices')
assert(messages[1]:find('1.5.2%-expanded%.3'), 'update notice used the wrong manifest value')
assert(messages[2]:find(settings.downloadUrl, 1, true), 'download notice used the wrong URL')

messages = {}
remoteManifest = [[
fx_version 'cerulean'
version '1.5.2-expanded.2'
]]

dofile('server/version.lua')

assert(#messages == 0, 'current version should remain quiet by default')

print = originalPrint
print('version_check_spec.lua OK')
