--!strict
--[[
    Tux Physics Tails | Idle wag animation

    This module is cosmetic only. It does not change physics state or joints.
    In particular, wag offsets fade OUT while accelerating/turning, and
    fade back IN when stationary. Edit this file to change the wag pattern.

    The old engine's phase distortion is retained: paired low-frequency sine
    waves make the motion feel less like a rigid metronome.
]]
local Wag = {}

export type State = {
    Phase: number,
    Blend: number,
}

function Wag.NewState(phaseSeed: number): State
    return { Phase = phaseSeed, Blend = 0 }
end

function Wag.Reset(state: State): ()
    state.Blend = 0
end

function Wag.Step(
    state: State,
    dt: number,
    speed: number,
    amplitude: Vector3,
    blendSpeed: number,
    activity: number,
    motionThreshold: number
): Vector3
    if dt <= 0 then
        return Vector3.zero
    end

    state.Phase += dt * speed * (2 * math.pi)
    local wanted = 1 - math.clamp(activity / math.max(motionThreshold, 1e-5), 0, 1)
    local mix = 1 - math.exp(-blendSpeed * dt)
    state.Blend += (wanted - state.Blend) * mix

    local phase = state.Phase
    local t = phase + math.sin(phase) * math.sin(phase * 0.22727272727272727) * 0.9
    return Vector3.new(
        (math.sin(t * 2) + 0.8) * amplitude.X,
        math.cos(t) * amplitude.Y,
        -math.sin(t) * amplitude.Z
    ) * state.Blend
end

return table.freeze(Wag)
