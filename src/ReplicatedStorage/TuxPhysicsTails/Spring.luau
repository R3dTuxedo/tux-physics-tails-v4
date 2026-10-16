--!strict
-- Tux Physics Tails | Spring
-- Analytic solution to a damped harmonic oscillator.
--
-- Unlike frame-dependent Euler integration, this solution is stable for very
-- large/small dt and behaves essentially the same at different frame rates.
-- Position, target and velocity are Vector3 values in *radians* and radians/s.

local Spring = {}

function Spring.Step(
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	frequencyHz: number,
	dampingRatio: number,
	dt: number
): (Vector3, Vector3)
	if dt <= 0 then
		return position, velocity
	end

	local omega = frequencyHz * (2 * math.pi)
	local displacement = position - target

	-- Disabling the spring means holding its current displacement, not NaN.
	if omega < 1e-5 then
		return position, Vector3.zero
	end

	if dampingRatio < 0.9999 then
		-- Underdamped (oscillates around the target).
		local decay = dampingRatio * omega
		local dampedOmega = omega * math.sqrt(1 - dampingRatio * dampingRatio)
		local b = (velocity + displacement * decay) / dampedOmega
		local c = math.cos(dampedOmega * dt)
		local s = math.sin(dampedOmega * dt)
		local attenuation = math.exp(-decay * dt)

		return target + (displacement * c + b * s) * attenuation,
			(velocity * c - (b * decay + displacement * dampedOmega) * s) * attenuation
	elseif dampingRatio < 1.0001 then
		-- Critically damped (fastest no-overshoot return to the target).
		local change = velocity + displacement * omega
		local attenuation = math.exp(-omega * dt)
		return target + (displacement + change * dt) * attenuation,
			(velocity - change * (omega * dt)) * attenuation
	else
		-- Overdamped (slower return, without oscillating).
		local root = math.sqrt(dampingRatio * dampingRatio - 1)
		local r1 = -omega * (dampingRatio - root)
		local r2 = -omega * (dampingRatio + root)
		local a = (velocity - displacement * r2) / (r1 - r2)
		local b = displacement - a
		local e1 = math.exp(r1 * dt)
		local e2 = math.exp(r2 * dt)
		return target + a * e1 + b * e2, a * (r1 * e1) + b * (r2 * e2)
	end
end

return Spring
