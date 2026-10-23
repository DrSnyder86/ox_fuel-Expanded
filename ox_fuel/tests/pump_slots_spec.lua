package.path = './?.lua;./?/init.lua;' .. package.path

local pumpSlots = require 'pump_slots'
local settings = {
	dualNozzles = true,
	sharedFlowMultiplier = 0.65,
	singleNozzleModels = {
		[12345] = true,
	},
}

assert(pumpSlots.getSlotCount(settings, 12345) == 1, 'configured vintage model should have one slot')
assert(pumpSlots.getSlotCount(settings, 67890) == 2, 'ordinary pumps should have two slots')
assert(pumpSlots.getSlotCount({ dualNozzles = false }, 67890) == 1, 'dual-nozzle master switch was ignored')
assert(pumpSlots.getLeaseKey('pump', 1) == 'pump#1', 'slot one key is incorrect')
assert(pumpSlots.getLeaseKey('pump', 2) == 'pump#2', 'slot two key is incorrect')
assert(pumpSlots.getPreferredSlot(-0.1) == 1, 'left-side player should prefer slot one')
assert(pumpSlots.getPreferredSlot(0.1) == 2, 'right-side player should prefer slot two')
assert(math.abs(pumpSlots.getSharedFlowMultiplier(settings) - 0.65) < 0.0001, 'shared multiplier is incorrect')

local lease = { owner = 21, token = '21:1', model = 67890, expiresAt = 1000 }
assert(pumpSlots.canSetConnectorTaken(lease, 21, '21:1', 67890, 900), 'valid connector owner rejected')
assert(not pumpSlots.canSetConnectorTaken(lease, 22, '21:1', 67890, 900), 'another player can change the dock')
assert(not pumpSlots.canSetConnectorTaken(lease, 21, 'bad', 67890, 900), 'invalid token can change the dock')
assert(not pumpSlots.canSetConnectorTaken(lease, 21, '21:1', 12345, 900), 'gas pump accepted as charger')
assert(not pumpSlots.canSetConnectorTaken(lease, 21, '21:1', 67890, 1001), 'expired lease accepted')
assert(not pumpSlots.canSetConnectorTaken(nil, 21, '21:1', 67890, 900), 'missing lease accepted')

print('pump_slots_spec.lua OK')
