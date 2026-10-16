--!strict
--[[
    Tux Physics Tails | Defaults
    Copyright (c) 2026 @R3dTuxedo

    Edit these values before publishing, or use Tails.Configure(),
    Tails.SetDefaults() and controller:SetOptions() from a LocalScript.
    All settings are local to each observing client.
]]

local Types = require(script.Parent.Types)
type Options = Types.Options
type Configuration = Types.Configuration

local DetectionAndPerformance: Configuration = {
    AutoPlayers = true,
    AutoDetect = true,
    RequireAccessoryType = true, -- Back or Waist
    NameKeyword = "tail", -- Case-insensitive substring
    IncludedAccessoryNames = {}, -- E.g. "cube.003accessory"
    Enabled = true,
    MaxDistance = 240, -- Camera distance in studs; math.huge disables distance culling
    MaxVisibleTails = 200, -- Nearest eligible tails
    MaxFrameGap = 0.15, -- Large pauses reset smoothly rather than injecting huge impulses
}

local TailDefaults: Options = {
    Frequency = 2.6, -- Spring frequency in Hz
    DampingRatio = 0.72, -- 1 = critically damped; < 1 = elastic
    TimeScale = 1,
    MaxAngle = math.rad(42),
    LinearInfluence = Vector3.new(0.009, 0.012, 0.009),
	AngularInfluence = Vector3.new(0.255, 0.36, 0.255),
	AngularAccelerationInfluence = Vector3.new(0.018, 0.018, 0.018),
    VelocitySmoothing = 17,
    GravityScale = 0.12, -- only the DIFFERENCE from NeutralGravity creates gravitational droop
    NeutralGravity = 196.2, -- standard Roblox gravity: zero additional torque at rest
    WindEnabled = true, -- read workspace.GlobalWind; CustomWind works even if this is false
    CustomWind = Vector3.zero, -- additive wind (world space); does not change workspace.GlobalWind
    WindInfluence = 1, -- multiplier for the original Tux fluctuating wind response
    ExternalAcceleration = Vector3.zero, -- World-space studs/s^2
    TeleportDistance = 12,
    TeleportAngle = math.rad(125),
    WagEnabled = true,
    WagAmplitude = Vector3.new(0.07, 0.16, 0.04), -- Radians
    WagSpeed = 0.2,
    WagBlendSpeed = 3.2,
    WagMotionThreshold = 3,
    AxisFrame = CFrame.identity, -- Rotation relative to the body/root
    MassOffset = Vector3.zero, -- Approximate centre of mass in tail-part local space
    ScaleWithCharacter = false, -- Keep false for avatar constraints; Roblox owns avatar scaling
}

return {
    Engine = DetectionAndPerformance,
    Tail = TailDefaults,
}
