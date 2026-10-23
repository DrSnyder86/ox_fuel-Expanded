package.path = './?.lua;./?/init.lua;' .. package.path

local pumpFlow = require 'pump_flow'
local session = {
	startedAt = 1000,
	flowSegments = {
		{ startTick = 1, amountPerTick = 1.0 },
	},
	flowPerTick = 1.0,
}

assert(pumpFlow.getMaxTicks(10, 1, 0.5) == 20, 'minimum shared flow was not included in max ticks')

local startTick, changed = pumpFlow.setRate(session, 2499, 500, 0.65)

assert(changed and startTick == 4, 'mid-session rate should begin on the next transfer tick')
assert(math.abs(pumpFlow.getTransferredAmount(session, 6) - 4.95) < 0.0001, 'mixed full/shared flow total is incorrect')

startTick, changed = pumpFlow.setRate(session, 3499, 500, 1.0)

assert(changed and startTick == 6, 'restored flow should begin on the next transfer tick')
assert(math.abs(pumpFlow.getTransferredAmount(session, 8) - 7.3) < 0.0001, 'restored flow total is incorrect')

print('pump_flow_spec.lua OK')
