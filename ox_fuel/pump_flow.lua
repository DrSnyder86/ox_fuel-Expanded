local pumpFlow = {}

function pumpFlow.getMaxTicks(maxAmount, baseAmountPerTick, minimumMultiplier)
	maxAmount = math.max(tonumber(maxAmount) or 0, 0)
	baseAmountPerTick = math.max(tonumber(baseAmountPerTick) or 0, 0)
	minimumMultiplier = math.min(math.max(tonumber(minimumMultiplier) or 1, 0.1), 1)

	if maxAmount <= 0 or baseAmountPerTick <= 0 then return 0 end

	return math.ceil(maxAmount / (baseAmountPerTick * minimumMultiplier))
end

function pumpFlow.setRate(session, now, refillTick, amountPerTick, startTickOverride)
	if type(session) ~= 'table' then return end

	refillTick = math.max(tonumber(refillTick) or 1, 1)
	amountPerTick = math.max(tonumber(amountPerTick) or 0, 0)
	now = tonumber(now) or session.startedAt or 0

	local startTick = tonumber(startTickOverride)
		or math.floor((now - (session.startedAt or now)) / refillTick) + 2
	startTick = math.max(math.floor(startTick), 1)
	local segments = session.flowSegments or {}
	local last = segments[#segments]

	if last and math.abs((last.amountPerTick or 0) - amountPerTick) <= 0.0000001 then
		session.flowPerTick = amountPerTick
		return startTick, false
	end

	if last and last.startTick == startTick then
		last.amountPerTick = amountPerTick
	else
		segments[#segments + 1] = {
			startTick = startTick,
			amountPerTick = amountPerTick,
		}
	end

	session.flowSegments = segments
	session.flowPerTick = amountPerTick

	return startTick, true
end

function pumpFlow.getTransferredAmount(session, completedTicks)
	completedTicks = math.max(math.floor(tonumber(completedTicks) or 0), 0)

	if completedTicks <= 0 then return 0 end

	local segments = type(session) == 'table' and session.flowSegments or nil

	if type(segments) ~= 'table' or #segments == 0 then
		return completedTicks * math.max(tonumber(session and session.flowPerTick) or 0, 0)
	end

	local amount = 0

	for index = 1, #segments do
		local segment = segments[index]
		local startTick = math.max(math.floor(tonumber(segment.startTick) or 1), 1)
		local nextSegment = segments[index + 1]
		local endTick = math.min(
			completedTicks,
			nextSegment and math.max(math.floor(tonumber(nextSegment.startTick) or startTick) - 1, startTick - 1) or completedTicks
		)

		if endTick >= startTick then
			amount = amount + ((endTick - startTick + 1) * math.max(tonumber(segment.amountPerTick) or 0, 0))
		end
	end

	return amount
end

return pumpFlow
