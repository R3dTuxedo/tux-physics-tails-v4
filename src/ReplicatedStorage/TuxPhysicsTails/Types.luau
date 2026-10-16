--!strict
--[[
    Tux Physics Tails | Public types
    Copyright (c) 2026 @R3dTuxedo

    Shared type contracts are kept in one place so projects using Rojo can
    autocomplete methods and catch misspelled options under --!strict.
    This module exports types only; requiring it has no side effects.
]]

export type Options = {
    Frequency: number,
    DampingRatio: number,
    TimeScale: number,
    MaxAngle: number,
    LinearInfluence: Vector3,
    AngularInfluence: Vector3,
    AngularAccelerationInfluence: Vector3,
    VelocitySmoothing: number,
    GravityScale: number,
    NeutralGravity: number, -- baseline gravitational acceleration (studs/s²) at which there is no droop
    WindEnabled: boolean,
    CustomWind: Vector3,
    WindInfluence: number,
    ExternalAcceleration: Vector3,
    TeleportDistance: number,
    TeleportAngle: number,
    WagEnabled: boolean,
    WagAmplitude: Vector3,
    WagSpeed: number,
    WagBlendSpeed: number,
    WagMotionThreshold: number,
    AxisFrame: CFrame,
    MassOffset: Vector3,
    ScaleWithCharacter: boolean,
}

-- Public option overrides: every field can be omitted.
export type OptionPatch = {
    Frequency: number?,
    DampingRatio: number?,
    TimeScale: number?,
    MaxAngle: number?,
    LinearInfluence: Vector3?,
    AngularInfluence: Vector3?,
    AngularAccelerationInfluence: Vector3?,
    VelocitySmoothing: number?,
    GravityScale: number?,
    NeutralGravity: number?,
    WindEnabled: boolean?,
    CustomWind: Vector3?,
    WindInfluence: number?,
    ExternalAcceleration: Vector3?,
    TeleportDistance: number?,
    TeleportAngle: number?,
    WagEnabled: boolean?,
    WagAmplitude: Vector3?,
    WagSpeed: number?,
    WagBlendSpeed: number?,
    WagMotionThreshold: number?,
    AxisFrame: CFrame?,
    MassOffset: Vector3?,
    ScaleWithCharacter: boolean?,
}

export type Configuration = {
    AutoPlayers: boolean,
    AutoDetect: boolean,
    RequireAccessoryType: boolean,
    NameKeyword: string,
    IncludedAccessoryNames: { string },
    Enabled: boolean,
    MaxDistance: number,
    MaxVisibleTails: number,
    MaxFrameGap: number,
}

export type ConfigurationPatch = {
    AutoPlayers: boolean?,
    AutoDetect: boolean?,
    RequireAccessoryType: boolean?,
    NameKeyword: string?,
    IncludedAccessoryNames: { string }?,
    Enabled: boolean?,
    MaxDistance: number?,
    MaxVisibleTails: number?,
    MaxFrameGap: number?,
}

export type Registration = {
    -- Registration fields and individual physics overrides share one flat record.
    Frequency: number?,
    DampingRatio: number?,
    TimeScale: number?,
    MaxAngle: number?,
    LinearInfluence: Vector3?,
    AngularInfluence: Vector3?,
    AngularAccelerationInfluence: Vector3?,
    VelocitySmoothing: number?,
    GravityScale: number?,
    NeutralGravity: number?,
    WindEnabled: boolean?,
    CustomWind: Vector3?,
    WindInfluence: number?,
    ExternalAcceleration: Vector3?,
    TeleportDistance: number?,
    TeleportAngle: number?,
    WagEnabled: boolean?,
    WagAmplitude: Vector3?,
    WagSpeed: number?,
    WagBlendSpeed: number?,
    WagMotionThreshold: number?,
    AxisFrame: CFrame?,
    MassOffset: Vector3?,
    ScaleWithCharacter: boolean?,
    Pivot: (CFrame | Attachment)?,
    TipAttachment: (Vector3 | Attachment)?,
    Character: Model?,
    Accessory: Accessory?,
    Root: BasePart?,
    Tail: BasePart?,
    Enabled: boolean?,
}

export type State = {
    Enabled: boolean,
    Active: boolean,
    Angle: Vector3,
    AngularVelocity: Vector3,
    Pivot: CFrame,
    Lever: Vector3,
    Root: BasePart,
    Part: BasePart,
    Joint: Weld | ManualWeld,
    SourceConstraint: RigidConstraint?,
    Character: Model?,
    Accessory: Accessory?,
}

export type Controller = {
    Root: BasePart,
    Part: BasePart,
    Joint: Weld | ManualWeld,
    SourceConstraint: RigidConstraint?,
    Accessory: Accessory?,
    Character: Model?,
    Enabled: boolean,
    SetOptions: (self: Controller, patch: OptionPatch) -> (),
    GetOptions: (self: Controller) -> Options,
    SetEnabled: (self: Controller, enabled: boolean) -> (),
    SetPivot: (self: Controller, pivot: CFrame | Attachment) -> (),
    SetTip: (self: Controller, tip: Vector3 | Attachment) -> (),
    Reset: (self: Controller) -> (),
    GetState: (self: Controller) -> State,
    Destroy: (self: Controller) -> (),
}

export type Stats = {
    Registered: number,
    Simulating: number,
    Running: boolean,
}

return table.freeze({})
