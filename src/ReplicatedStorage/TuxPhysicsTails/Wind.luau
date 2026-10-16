--!strict
--[[
    Tux Physics Tails | Wind response
    Written as a separate, easily editable module.

    Restores the characteristic Tux v3 gust effect: a slow fluctuating
    oscillation with an additional jitter component at stronger wind speeds.
    Direction and magnitude come from (GlobalWind + CustomWind).

    Magnitude is intentionally nonlinear (proportional to wind speed squared),
    matching the expressive behavior of the original engine. Use WindInfluence
    to tune the strength; 0 disables it. Zero wind always returns Vector3.zero
    (never call Vector3.zero.Unit).
]]
local Wind = {}

function Wind.Sample(wind: Vector3, timeSeconds: number, influence: number): Vector3
	local speed = wind.Magnitude
    if speed < 1e-5 or influence <= 0 then
        return Vector3.zero
	end
	local clampedSpeed = math.min(speed, 30) -- Prevents breaking wind effect under high wind.
	local windUnit = wind.Unit
	
	local baseWind = if speed > clampedSpeed then windUnit * clampedSpeed else wind

    local sinTime4 = math.sin(timeSeconds * 4)
	local unstable = math.sin(timeSeconds * 2 * sinTime4) * (clampedSpeed * 0.6)
    local stable = math.sin(timeSeconds * 2) * sinTime4
    local fluctuation = 1 + (stable + unstable) * 0.4

	const base = baseWind * (influence * 2)
	const offset = windUnit * 0.2 * clampedSpeed * fluctuation * influence

	return offset - base
end

return table.freeze(Wind)
