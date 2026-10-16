--!strict
--[[
    TUX PHYSICS TAILS 4.2  |  CLIENT ENGINE
    Copyright (c) 2026 @R3dTuxedo

    This is a procedural, CLIENT-SIDE animation engine for rigid tails.
    It does not use server Remotes or apply server-authoritative forces.

    Supported attachment paths:
      1. AccessoryRigidConstraint  (current Roblox accessory attachments)
      2. AccessoryWeld             (legacy accessory attachments)
      3. Existing Weld/ManualWeld  (manual registration)
      4. Any unanchored BasePart   (Attach() creates a private Weld)

    RIGID CONSTRAINT ADAPTER
    Constraints have Attachment0/Attachment1, not C0/C1. To animate an
    accessory without touching the avatar's shared rig attachments, we:
      * Capture both source attachments and their exact local CFrames.
      * Disable only that specific original constraint, locally.
      * Construct a private Weld with the equivalent rest relationship.
      * Animate the root-facing weld offset around a ROOT-LOCAL hinge.
      * On removal, destroy only our Weld and restore the original Enabled state.

    This avoids the fragile approach of modifying a shared body attachment
    (which may be used by other accessories and animation systems).

    Supported constraints must connect Attachments directly beneath BaseParts.
    Connections to skinned Bones are intentionally not rewritten into Welds.
    This is an individual rigid-tail solver, not a skinned-mesh/bone solver.

    REST FRAME GEOMETRY
      root.CFrame * rootOffset == tail.CFrame * tailOffset
      restRelative = rootOffset * tailOffset^-1
      motion = T(hinge) * basis * angularRotation * basis^-1 * T(-hinge)

    All translations and pivots live in root-part space, not mesh-part pivot
    space. Reversed Part0/Part1 on manually registered Welds work identically.

    See README.md for installation, typed API, limits and examples.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Types = require(script.Types)
local Spring = require(script.Spring)
local Wag = require(script.Wag)
local Wind = require(script.Wind)
local Defaults = require(script.Configuration)

type Options = Types.Options
type OptionPatch = Types.OptionPatch
type Configuration = Types.Configuration
type ConfigurationPatch = Types.ConfigurationPatch
type Registration = Types.Registration
type Controller = Types.Controller
type State = Types.State
type Stats = Types.Stats

type Joint = Weld | ManualWeld

type Geometry = {
    Pivot: (CFrame | Attachment)?,
    Tip: (Vector3 | Attachment)?,
    AutoPivot: CFrame?,
}

type Internal = {
    -- Public controller fields (duplicated instead of intersecting public
    -- methods with private state: this avoids Luau recursive-metatable cycles).
    Root: BasePart,
    Part: BasePart,
    Joint: Weld | ManualWeld,
    SourceConstraint: RigidConstraint?,
    Accessory: Accessory?,
    Character: Model?,
    Enabled: boolean,
    SetOptions: (self: Internal, patch: OptionPatch) -> (),
    GetOptions: (self: Internal) -> Options,
    SetEnabled: (self: Internal, enabled: boolean) -> (),
    SetPivot: (self: Internal, pivot: CFrame | Attachment) -> (),
    SetTip: (self: Internal, tip: Vector3 | Attachment) -> (),
    Reset: (self: Internal) -> (),
    GetState: (self: Internal) -> State,
    Destroy: (self: Internal) -> (),
    _disposed: boolean,
    _createdWeld: boolean,
    _rootIsPart0: boolean,
    _originalC0: CFrame,
    _originalC1: CFrame,
    _restRelative: CFrame,
    _sourceEnabled: boolean?,
    _rootSource: Attachment?,
    _tailSource: Attachment?,
    _overrides: OptionPatch,
    _options: Options,
    _geometry: Geometry,
    _pivot: CFrame,
    _axis: CFrame,
    _lever: Vector3,
    _initialScale: number,
    _angles: Vector3,
    _springVelocity: Vector3,
    _rootPrevious: CFrame,
    _linearVelocity: Vector3,
    _angularRootVelocity: Vector3,
    _wag: Wag.State,
    _windTime: number,
    _awake: boolean,
    _distanceSquared: number,
    _writtenScale: number?,
    _connections: { RBXScriptConnection },
    _scaledOffsets: (self: Internal, scale: number) -> (CFrame, CFrame),
    _scaleFactor: (self: Internal) -> number,
    _restore: (self: Internal) -> (),
    _write: (self: Internal, angles: Vector3) -> (),
    _recomputeGeometry: (self: Internal) -> (),
    _resetState: (self: Internal) -> (),
    _park: (self: Internal) -> (),
    _step: (self: Internal, dt: number) -> (),
    _refreshSource: (self: Internal) -> (),
}

type AccessoryWatch = {
    Character: Model,
    Connections: { RBXScriptConnection },
    JointConnections: { RBXScriptConnection },
    TryRegister: () -> (),
}

local Engine = {}
local ControllerMethods = {}
ControllerMethods.__index = ControllerMethods

-- Runtime validation is important even in a typed library: ordinary scripts
-- may pass tables that were created dynamically or without --!strict.
local OPTION_KINDS: { [string]: string } = {
    Frequency = "number", DampingRatio = "number", TimeScale = "number",
    MaxAngle = "number", LinearInfluence = "Vector3", AngularInfluence = "Vector3",
    AngularAccelerationInfluence = "Vector3", VelocitySmoothing = "number",
    GravityScale = "number", NeutralGravity = "number",
    WindEnabled = "boolean", CustomWind = "Vector3", WindInfluence = "number",
    ExternalAcceleration = "Vector3", TeleportDistance = "number",
    TeleportAngle = "number", WagEnabled = "boolean",
    WagAmplitude = "Vector3", WagSpeed = "number", WagBlendSpeed = "number",
    WagMotionThreshold = "number", AxisFrame = "CFrame",
    MassOffset = "Vector3", ScaleWithCharacter = "boolean",
}

local NONNEGATIVE: { [string]: boolean } = {
    Frequency = true, DampingRatio = true, TimeScale = true,
    MaxAngle = true, VelocitySmoothing = true, GravityScale = true, NeutralGravity = true,
    WindInfluence = true, TeleportDistance = true, TeleportAngle = true,
    WagSpeed = true, WagBlendSpeed = true, WagMotionThreshold = true,
}

local CONFIG_KINDS: { [string]: string } = {
    AutoPlayers = "boolean", AutoDetect = "boolean",
    RequireAccessoryType = "boolean", NameKeyword = "string",
    IncludedAccessoryNames = "table", Enabled = "boolean",
    MaxDistance = "number", MaxVisibleTails = "number", MaxFrameGap = "number",
}

local REGISTER_KEYS: { [string]: boolean } = {
    Pivot = true, TipAttachment = true, Character = true,
    Accessory = true, Root = true, Tail = true, Enabled = true,
}

local function finite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function finiteVector(value: Vector3): boolean
    return finite(value.X) and finite(value.Y) and finite(value.Z)
end

local function validateOptions(patch: OptionPatch): ()
    assert(type(patch) == "table", "TuxPhysicsTails: expected options table")
    local dynamic = patch :: { [string]: unknown }
    for key, value in pairs(dynamic) do
        local kind = OPTION_KINDS[key]
        assert(kind ~= nil, "TuxPhysicsTails: unknown tail setting " .. key)
        assert(typeof(value) == kind, "TuxPhysicsTails: invalid type for " .. key)
        if kind == "number" then
            local numberValue = value :: number
            assert(finite(numberValue), "TuxPhysicsTails: non-finite " .. key)
            assert(not NONNEGATIVE[key] or numberValue >= 0, "TuxPhysicsTails: negative " .. key)
        elseif kind == "Vector3" then
            assert(finiteVector(value :: Vector3), "TuxPhysicsTails: non-finite " .. key)
        elseif kind == "CFrame" then
            local frame = value :: CFrame
            local components = { frame:GetComponents() }
            for _, component in ipairs(components) do
                assert(finite(component), "TuxPhysicsTails: non-finite " .. key)
            end
        end
    end
end

local function validateConfiguration(patch: ConfigurationPatch): ()
    assert(type(patch) == "table", "TuxPhysicsTails: expected configuration table")
    local dynamic = patch :: { [string]: unknown }
    for key, value in pairs(dynamic) do
        local kind = CONFIG_KINDS[key]
        assert(kind ~= nil and typeof(value) == kind, "TuxPhysicsTails: invalid configuration " .. key)
        if kind == "number" then
            local numberValue = value :: number
            assert(numberValue >= 0 and (finite(numberValue) or (key == "MaxDistance" and numberValue == math.huge)),
                "TuxPhysicsTails: non-finite or negative " .. key)
        elseif key == "IncludedAccessoryNames" then
            for _, name in ipairs(value :: { unknown }) do
                assert(type(name) == "string", "TuxPhysicsTails: IncludedAccessoryNames must contain strings")
            end
        end
    end
end

-- Merging separate complete/partial records keeps this file fully typed.
-- Input keys are validated before being copied through the string-index view.
local function mergeOptions(base: Options, patch: OptionPatch): Options
    local result: Options = table.clone(base)
    local values = result :: { [string]: unknown }
    for key, value in pairs(patch :: { [string]: unknown }) do
        values[key] = value
    end
    return result
end

local function mergeOverrides(base: OptionPatch, patch: OptionPatch): OptionPatch
    local result: OptionPatch = table.clone(base)
    local values = result :: { [string]: unknown }
    for key, value in pairs(patch :: { [string]: unknown }) do
        values[key] = value
    end
    return result
end

local function mergeConfiguration(base: Configuration, patch: ConfigurationPatch): Configuration
    local result: Configuration = table.clone(base)
    local values = result :: { [string]: unknown }
    for key, value in pairs(patch :: { [string]: unknown }) do
        values[key] = value
    end
    return result
end

local function asMap(tableValue: unknown): { [string]: unknown }
    return tableValue :: { [string]: unknown }
end

local settings: Configuration = table.clone(Defaults.Engine)
settings.IncludedAccessoryNames = table.clone(Defaults.Engine.IncludedAccessoryNames)
local defaultOptions: Options = table.clone(Defaults.Tail)

local includeNames: { [string]: boolean } = {}
local function rebuildNames(): ()
    table.clear(includeNames)
    for _, name in ipairs(settings.IncludedAccessoryNames) do
        includeNames[string.lower(name)] = true
    end
end
rebuildNames()

local tails: { Internal } = {}
local byJoint: { [Instance]: Internal } = {}
local byPart: { [BasePart]: Internal } = {}
local byAccessory: { [Accessory]: Internal } = {}
local bySource: { [RigidConstraint]: Internal } = {}
-- Weak keys avoid retaining disabled players/characters/accessories forever
-- after a streamed-out character or deleted accessory disappears.
local ignoredPlayers = setmetatable({} :: { [Player]: boolean }, { __mode = "k" })
local ignoredCharacters = setmetatable({} :: { [Model]: boolean }, { __mode = "k" })
local ignoredAccessories = setmetatable({} :: { [Accessory]: boolean }, { __mode = "k" })
local playerWatches: { [Player]: RBXScriptConnection } = {}
local characterWatches: { [Model]: { RBXScriptConnection } } = {}
local accessoryWatches: { [Accessory]: AccessoryWatch } = {}
local containerWatches: { [Instance]: { RBXScriptConnection } } = {}
local sharedConnections: { RBXScriptConnection } = {}
local renderConnection: RBXScriptConnection? = nil
local running = false

local function currentOptions(overrides: OptionPatch): Options
    return mergeOptions(defaultOptions, overrides)
end

local function scaledFrame(frame: CFrame, factor: number): CFrame
    return frame.Rotation + frame.Position * factor
end

local function getModelScale(model: Model?): number
    if model == nil then return 1 end
    local ok, result = pcall(function(): number
        return model:GetScale()
    end)
    if ok and typeof(result) == "number" and finite(result) and result > 0 then
        return result
    end
    return 1
end

local function findCharacter(root: BasePart): Model?
    local ancestor: Instance? = root
    while ancestor do
        if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
            return ancestor
        end
        ancestor = ancestor.Parent
    end
    return nil
end

local function finiteFrame(frame: CFrame): boolean
    local components = { frame:GetComponents() }
    for _, component in ipairs(components) do
        if not finite(component) then return false end
    end
    return true
end

local function chooseAttachmentFrame(value: CFrame | Attachment, root: BasePart, tail: BasePart, rest: CFrame): CFrame
    if typeof(value) == "CFrame" then return value end
    if value:IsDescendantOf(tail) then
        -- Resolve against the REST pose, not the currently animated pose.
        local localFromTail = tail.CFrame:ToObjectSpace(value.WorldCFrame)
        return rest * localFromTail
    end
    return root.CFrame:ToObjectSpace(value.WorldCFrame)
end

local function clampMagnitude(vector: Vector3, maximum: number): Vector3
    if maximum <= 0 then return Vector3.zero end
    local magnitude = vector.Magnitude
    return if magnitude > maximum then vector * (maximum / magnitude) else vector
end

local function seed(name: string): number
    local hash = 17
    for index = 1, #name do
        hash = (hash * 31 + string.byte(name, index)) % 65521
    end
    return hash * (2 * math.pi / 65521)
end

local function sameParts(joint: Joint, root: BasePart, part: BasePart): boolean
    return (joint.Part0 == root and joint.Part1 == part)
        or (joint.Part1 == root and joint.Part0 == part)
end

function ControllerMethods._scaledOffsets(self: Internal, factor: number): (CFrame, CFrame)
    return scaledFrame(self._originalC0, factor), scaledFrame(self._originalC1, factor)
end

function ControllerMethods._scaleFactor(self: Internal): number
    if self.SourceConstraint ~= nil or not self._options.ScaleWithCharacter then return 1 end
    return getModelScale(self.Character) / self._initialScale
end

function ControllerMethods._restore(self: Internal): ()
    if self.Joint.Parent == nil or not sameParts(self.Joint, self.Root, self.Part) then return end
    local factor = self:_scaleFactor()
    local c0, c1 = self:_scaledOffsets(factor)
    local joint = self.Joint :: any
    joint.C0 = c0
    joint.C1 = c1
    self._writtenScale = factor
end

function ControllerMethods._write(self: Internal, angles: Vector3): ()
    if self._disposed or self.Joint.Parent == nil then return end
    if not sameParts(self.Joint, self.Root, self.Part) then return end
    local factor = self:_scaleFactor()
    local c0, c1 = self:_scaledOffsets(factor)
    local joint = self.Joint :: any
    local hinge = self._pivot.Position * factor
    local basis = self._axis
    local rotate = CFrame.Angles(angles.X, angles.Y, angles.Z)
    local motion = CFrame.new(hinge) * basis * rotate * basis:Inverse() * CFrame.new(-hinge)

    if self._rootIsPart0 then
        if factor ~= self._writtenScale then joint.C1 = c1 end
        joint.C0 = motion * c0
    else
        if factor ~= self._writtenScale then joint.C0 = c0 end
        joint.C1 = motion * c1
    end
    self._writtenScale = factor
end

function ControllerMethods._recomputeGeometry(self: Internal): ()
    local geometry = self._geometry
    local point: CFrame?
    if geometry.Pivot ~= nil then
        point = chooseAttachmentFrame(geometry.Pivot, self.Root, self.Part, self._restRelative)
    else
        point = geometry.AutoPivot
    end
    if point == nil then
        point = if self._rootIsPart0 then self._originalC0 else self._originalC1
    end
    assert(point ~= nil)
    self._pivot = point
    self._axis = self._options.AxisFrame.Rotation

    local massPoint = self._restRelative:PointToWorldSpace(self._options.MassOffset)
    local tip = geometry.Tip
    if tip == nil then
        local found = self.Part:FindFirstChild("TailTip", true)
        if found and found:IsA("Attachment") then tip = found end
    end
    if tip ~= nil then
        local tipRoot: Vector3
        if typeof(tip) == "Vector3" then
            tipRoot = self._restRelative:PointToWorldSpace(tip)
        else
            local tipFrame = chooseAttachmentFrame(tip, self.Root, self.Part, self._restRelative)
            tipRoot = tipFrame.Position
        end
        massPoint = point.Position:Lerp(tipRoot, 0.62)
    end
    local lever = massPoint - point.Position
    if lever.Magnitude < 0.2 then
        -- The mesh origin can coincide with the hinge. Avoid zero torque.
        lever = Vector3.new(0, -0.2, math.max(0.7, self.Part.Size.Magnitude * 0.2))
    end
    self._lever = clampMagnitude(lever, 4)
end

function ControllerMethods._resetState(self: Internal): ()
    self._angles = Vector3.zero
    self._springVelocity = Vector3.zero
    self._rootPrevious = self.Root.CFrame
    self._linearVelocity = Vector3.zero
    self._angularRootVelocity = Vector3.zero
    Wag.Reset(self._wag)
end

function ControllerMethods._park(self: Internal): ()
    if not self._awake then return end
    self._awake = false
    self:_resetState()
    self:_restore()
end

function ControllerMethods._refreshSource(self: Internal): ()
    -- Avatar scaling/rebuilding can update the original attachment frames.
    -- Refresh the PRIVATE Weld from those original untouched attachments.
    local rootAttachment = self._rootSource
    local tailAttachment = self._tailSource
    if rootAttachment == nil or tailAttachment == nil then return end
    self._originalC0 = rootAttachment.CFrame
    self._originalC1 = tailAttachment.CFrame
    self._restRelative = self._originalC0 * self._originalC1:Inverse()
    -- Keep the inferred hinge synchronized with genuine avatar scale changes.
    if self._geometry.Pivot == nil then
        self._geometry.AutoPivot = rootAttachment.CFrame
    end
    self:_recomputeGeometry()
    self._awake = false
    self:_resetState()
    self:_restore()
end

function ControllerMethods._step(self: Internal, dt: number): ()
    if self._disposed then return end
    local currentRoot = self.Root.CFrame
    if not self._awake then
        self._awake = true
        self:_resetState()
        self:_write(Vector3.zero)
        return
    end
    if dt <= 0 or dt > settings.MaxFrameGap then
        self:_resetState()
        self:_write(Vector3.zero)
        return
    end

    local options = self._options
    local delta = self._rootPrevious:ToObjectSpace(currentRoot)
    local axis, angle = delta.Rotation:ToAxisAngle()
    if angle > math.pi then angle -= 2 * math.pi end
    local displacement = currentRoot.Position - self._rootPrevious.Position
    if displacement.Magnitude > options.TeleportDistance or math.abs(angle) > options.TeleportAngle then
        self:_resetState()
        self:_write(Vector3.zero)
        return
    end

    local rawVelocity = displacement / dt
    local rawTurn = axis * (angle / dt)
    local blend = 1 - math.exp(-options.VelocitySmoothing * dt)
    local linearVelocity = self._linearVelocity:Lerp(rawVelocity, blend)
    local angularVelocity = self._angularRootVelocity:Lerp(rawTurn, blend)
    local acceleration = (linearVelocity - self._linearVelocity) / dt
    local angularAcceleration = (angularVelocity - self._angularRootVelocity) / dt
    self._linearVelocity = linearVelocity
    self._angularRootVelocity = angularVelocity
    self._rootPrevious = currentRoot

    local accelerationWorld = options.ExternalAcceleration - acceleration
    -- Gravity is relative to the rest/reference gravity. At 196.2 (default),
    -- the imported rest pose remains neutral even when GravityScale > 0.
    -- Higher gravity causes more droop; lower gravity lifts the tail.
    if options.GravityScale > 0 then
        local deltaGravity = workspace.Gravity - options.NeutralGravity
        accelerationWorld += Vector3.new(0, -deltaGravity * options.GravityScale, 0)
    end

    self._windTime += dt * options.TimeScale
    if options.WindInfluence > 0 then
        local totalWind = options.CustomWind
        if options.WindEnabled then
            totalWind += workspace.GlobalWind
        end
        accelerationWorld -= Wind.Sample(totalWind, self._windTime, options.WindInfluence)
    end
    local basis = self._axis
    local accelerationBasis = basis:VectorToObjectSpace(currentRoot:VectorToObjectSpace(accelerationWorld))
    local leverBasis = basis:VectorToObjectSpace(self._lever * self:_scaleFactor())
    local turnBasis = basis:VectorToObjectSpace(angularVelocity)
    local turnAccelerationBasis = basis:VectorToObjectSpace(angularAcceleration)
    local target = leverBasis:Cross(accelerationBasis) * options.LinearInfluence
        - turnBasis * options.AngularInfluence
        - turnAccelerationBasis * options.AngularAccelerationInfluence
    target = clampMagnitude(target, options.MaxAngle)

    local simulatedTime = dt * options.TimeScale
    self._angles, self._springVelocity = Spring.Step(
        self._angles, self._springVelocity, target,
        options.Frequency, options.DampingRatio, simulatedTime
    )
    if self._angles.Magnitude > options.MaxAngle then
        self._angles = clampMagnitude(self._angles, options.MaxAngle)
        self._springVelocity *= 0.3
    end

    local finalAngle = self._angles
    if options.WagEnabled and options.TimeScale > 0 then
        local activity = acceleration.Magnitude * 0.018 + turnBasis.Magnitude * 1.2
        finalAngle += Wag.Step(self._wag, simulatedTime, options.WagSpeed,
            options.WagAmplitude, options.WagBlendSpeed, activity, options.WagMotionThreshold)
    else
        Wag.Reset(self._wag)
    end
    self:_write(clampMagnitude(finalAngle, options.MaxAngle))
end

function ControllerMethods.SetOptions(self: Internal, patch: OptionPatch): ()
    assert(not self._disposed, "TuxPhysicsTails: controller has been destroyed")
    validateOptions(patch)
    self._overrides = mergeOverrides(self._overrides, patch)
    self._options = currentOptions(self._overrides)
    if patch.AxisFrame ~= nil or patch.MassOffset ~= nil or patch.ScaleWithCharacter ~= nil then
        self:_recomputeGeometry()
        self:Reset()
    end
end

function ControllerMethods.GetOptions(self: Internal): Options
    return table.clone(self._options)
end

function ControllerMethods.SetEnabled(self: Internal, enabled: boolean): ()
    assert(type(enabled) == "boolean", "TuxPhysicsTails: SetEnabled expects boolean")
    if self._disposed then return end
    self.Enabled = enabled
    if not enabled then self:_park() end
end

function ControllerMethods.SetPivot(self: Internal, pivot: CFrame | Attachment): ()
    assert(typeof(pivot) == "CFrame" or (typeof(pivot) == "Instance" and pivot:IsA("Attachment")),
        "TuxPhysicsTails: Pivot must be a CFrame or Attachment")
    self._geometry.Pivot = pivot
    self:_recomputeGeometry()
    self:Reset()
end

function ControllerMethods.SetTip(self: Internal, tip: Vector3 | Attachment): ()
    assert(typeof(tip) == "Vector3" or (typeof(tip) == "Instance" and tip:IsA("Attachment")),
        "TuxPhysicsTails: tip must be a Vector3 or Attachment")
    self._geometry.Tip = tip
    self:_recomputeGeometry()
    self:Reset()
end

function ControllerMethods.Reset(self: Internal): ()
    if self._disposed then return end
    self._awake = false
    self:_resetState()
    self:_restore()
end

function ControllerMethods.GetState(self: Internal): State
    return {
        Enabled = self.Enabled,
        Active = self._awake,
        Angle = self._angles,
        AngularVelocity = self._springVelocity,
        Pivot = self._pivot,
        Lever = self._lever,
        Root = self.Root,
        Part = self.Part,
        Joint = self.Joint,
        SourceConstraint = self.SourceConstraint,
        Character = self.Character,
        Accessory = self.Accessory,
    }
end

function ControllerMethods.Destroy(self: Internal): ()
    Engine.Remove(self :: Controller)
end

local function validateRegistration(opts: Registration)
    assert(type(opts) == "table", "TuxPhysicsTails: registration expects a table")
    local dynamic = asMap(opts)
    local tailPatch: { [string]: unknown } = {}
    for key, value in pairs(dynamic) do
        if OPTION_KINDS[key] then
            tailPatch[key] = value
        else
            assert(REGISTER_KEYS[key], "TuxPhysicsTails: unknown registration field " .. key)
        end
    end
    validateOptions(tailPatch :: OptionPatch)
    if opts.Pivot ~= nil then
        assert(typeof(opts.Pivot) == "CFrame" or (typeof(opts.Pivot) == "Instance" and opts.Pivot:IsA("Attachment")),
            "TuxPhysicsTails: invalid Pivot")
        if typeof(opts.Pivot) == "CFrame" then
            assert(finiteFrame(opts.Pivot), "TuxPhysicsTails: non-finite Pivot")
        end
    end
    if opts.TipAttachment ~= nil then
        assert(typeof(opts.TipAttachment) == "Vector3" or
            (typeof(opts.TipAttachment) == "Instance" and opts.TipAttachment:IsA("Attachment")),
            "TuxPhysicsTails: invalid TipAttachment")
    end
    if opts.Character ~= nil then assert(opts.Character:IsA("Model"), "invalid Character") end
    if opts.Accessory ~= nil then assert(opts.Accessory:IsA("Accessory"), "invalid Accessory") end
    if opts.Enabled ~= nil then assert(type(opts.Enabled) == "boolean", "invalid Enabled") end
end

local function buildController(
    joint: Joint, root: BasePart, part: BasePart, opts: Registration,
    createdWeld: boolean, source: RigidConstraint?, rootAttachment: Attachment?,
    tailAttachment: Attachment?, originalEnabled: boolean?, autoPivot: CFrame?
): Internal
    validateRegistration(opts)
    local existing = byJoint[joint]
    if existing then return existing end
    assert(byPart[part] == nil, "TuxPhysicsTails: part already has a tail controller")
    assert(not part.Anchored and root ~= part, "TuxPhysicsTails: tail must be a separate, unanchored part")
    assert(sameParts(joint, root, part), "TuxPhysicsTails: joint does not connect root and tail")

    local overrides: OptionPatch = {}
    local overrideMap = asMap(overrides)
    for key, value in pairs(asMap(opts)) do
        if OPTION_KINDS[key] then overrideMap[key] = value end
    end
    local isRoot0 = joint.Part0 == root
    local c0 = joint.C0
    local c1 = joint.C1
    local relative = if isRoot0 then c0 * c1:Inverse() else c1 * c0:Inverse()
    local character = opts.Character or findCharacter(root)
    local item = (setmetatable({
        Root = root, Part = part, Joint = joint,
        SourceConstraint = source, Accessory = opts.Accessory, Character = character,
        Enabled = opts.Enabled ~= false,
        _disposed = false, _createdWeld = createdWeld, _rootIsPart0 = isRoot0,
        _originalC0 = c0, _originalC1 = c1, _restRelative = relative,
        _sourceEnabled = originalEnabled, _rootSource = rootAttachment, _tailSource = tailAttachment,
        _overrides = overrides, _options = currentOptions(overrides),
        _geometry = { Pivot = opts.Pivot, Tip = opts.TipAttachment, AutoPivot = autoPivot } :: Geometry,
        _pivot = CFrame.identity, _axis = CFrame.identity, _lever = Vector3.zAxis,
        _initialScale = getModelScale(character),
        _angles = Vector3.zero, _springVelocity = Vector3.zero,
        _rootPrevious = root.CFrame, _linearVelocity = Vector3.zero,
        _angularRootVelocity = Vector3.zero,
        _wag = Wag.NewState(seed(part.Name .. joint:GetFullName())),
        _windTime = seed(part.Name) * 0.13,
        _awake = false, _distanceSquared = 0,
        _writtenScale = nil, _connections = {} :: { RBXScriptConnection },
    }, ControllerMethods) :: any) :: Internal
    item:_recomputeGeometry()
    table.insert(tails, item)
    byJoint[joint] = item
    byPart[part] = item
    if item.Accessory ~= nil then byAccessory[item.Accessory] = item end
    if source then bySource[source] = item end

    local function verify()
        if item._disposed then return end
        if joint.Parent == nil or root.Parent == nil or part.Parent == nil or not sameParts(joint, root, part) then
            item:Destroy()
        elseif source then
            local first, second = source.Attachment0, source.Attachment1
            if source.Parent == nil or first == nil or second == nil
                or (first ~= rootAttachment and first ~= tailAttachment)
                or (second ~= rootAttachment and second ~= tailAttachment) then
                item:Destroy()
                local accessory = item.Accessory
                local watcher = if accessory then accessoryWatches[accessory] else nil
                if watcher then task.defer(watcher.TryRegister) end
            end
        end
    end
    local c = item._connections
    table.insert(c, joint.AncestryChanged:Connect(verify))
    table.insert(c, root.AncestryChanged:Connect(verify))
    table.insert(c, part.AncestryChanged:Connect(verify))
    table.insert(c, joint:GetPropertyChangedSignal("Part0"):Connect(verify))
    table.insert(c, joint:GetPropertyChangedSignal("Part1"):Connect(verify))
    if source ~= nil then
        table.insert(c, source.AncestryChanged:Connect(verify))
        table.insert(c, source:GetPropertyChangedSignal("Attachment0"):Connect(verify))
        table.insert(c, source:GetPropertyChangedSignal("Attachment1"):Connect(verify))
        table.insert(c, source:GetPropertyChangedSignal("Enabled"):Connect(function()
            if source.Enabled and not item._disposed then
                -- Avoid simultaneously active weld and constraint if another
                -- script takes ownership of the original connection.
                item:Destroy()
            end
        end))
        if rootAttachment then
            table.insert(c, rootAttachment:GetPropertyChangedSignal("CFrame"):Connect(function()
                if not item._disposed then item:_refreshSource() end
            end))
        end
        if tailAttachment then
            table.insert(c, tailAttachment:GetPropertyChangedSignal("CFrame"):Connect(function()
                if not item._disposed then item:_refreshSource() end
            end))
        end
    end
    if item.Accessory then
        local accessory = item.Accessory
        table.insert(c, accessory.AncestryChanged:Connect(function()
            if accessory.Parent == nil or (character and not accessory:IsDescendantOf(character)) then
                item:Destroy()
            end
        end))
    end
    if character then
        table.insert(c, character.AncestryChanged:Connect(function()
            if character.Parent == nil then item:Destroy() end
        end))
    end
    item:_restore()
    return item
end

function Engine.GetTail(value: Controller | Instance): Controller?
    if typeof(value) ~= "Instance" then
        local internal = value :: Internal
        -- A controller is valid only if it is still indexed by the engine.
        -- Avoid getmetatable() here: Luau's metatable type-function requires
        -- a metatable-bearing static type and was rejecting the old record.
        if not internal._disposed and byPart[internal.Part] == internal then
            return internal :: Controller
        end
        return nil
    end
    local found: Internal? = byJoint[value]
    if value:IsA("BasePart") then
        found = found or byPart[value]
    elseif value:IsA("Accessory") then
        found = found or byAccessory[value]
    elseif value:IsA("RigidConstraint") then
        found = found or bySource[value]
    end
    return if found ~= nil then found :: Controller else nil
end

function Engine.Remove(value: Controller | Instance): boolean
    local controller = Engine.GetTail(value)
    if controller == nil then return false end
    local item = controller :: Internal
    item._disposed = true
    for _, connection in ipairs(item._connections) do connection:Disconnect() end
    table.clear(item._connections)
    -- Private adapter Weld is removed BEFORE restoring the original constraint.
    -- Otherwise two rigid connections can fight for the same Handle.
    if item._createdWeld then
        item.Joint:Destroy()
    else
        item:_restore()
    end
    if item.SourceConstraint and item.SourceConstraint.Parent and item._sourceEnabled ~= nil then
        item.SourceConstraint.Enabled = item._sourceEnabled
    end
    byJoint[item.Joint] = nil
    byPart[item.Part] = nil
    if item.SourceConstraint then bySource[item.SourceConstraint] = nil end
    if item.Accessory and byAccessory[item.Accessory] == item then
        byAccessory[item.Accessory] = nil
    end
    local index = table.find(tails, item)
    if index then table.remove(tails, index) end
    return true
end

function Engine.RegisterWeld(joint: Weld | ManualWeld, options: Registration?): Controller
    assert(joint:IsA("Weld") or joint:IsA("ManualWeld"), "TuxPhysicsTails: expected Weld/ManualWeld")
    local found = byJoint[joint]
    if found then return found :: Controller end
    local opts: Registration = options or {}
    local part0, part1 = joint.Part0, joint.Part1
    assert(part0 and part1, "TuxPhysicsTails: joint Part0/Part1 are not ready")
    local root: BasePart? = opts.Root
    local part: BasePart? = opts.Tail
    if root == nil and part == nil then
        if part0:FindFirstAncestorOfClass("Accessory") and not part1:FindFirstAncestorOfClass("Accessory") then
            root, part = part1, part0
        else
            root, part = part0, part1
        end
    elseif root == nil then
        root = if part == part0 then part1 else part0
    elseif not part then
        part = if root == part0 then part1 else part0
    end
    assert(root ~= nil and part ~= nil, "TuxPhysicsTails: missing root or tail")
    return buildController(joint, root, part, opts, false, nil, nil, nil, nil, nil) :: Controller
end

local function directAttachmentPart(attachment: Attachment?): BasePart?
    if attachment == nil or attachment:IsA("Bone") then return nil end
    -- A Bone may inherit Attachment, but its frame is animated and should
    -- not be approximated as a fixed local attachment on a BasePart.
    return if attachment.Parent and attachment.Parent:IsA("BasePart") then attachment.Parent else nil
end

function Engine.RegisterRigidConstraint(constraint: RigidConstraint, options: Registration?): (Controller?, string?)
    assert(constraint:IsA("RigidConstraint"), "TuxPhysicsTails: expected RigidConstraint")
    local opts: Registration = options or {}
    validateRegistration(opts)
    local a0, a1 = constraint.Attachment0, constraint.Attachment1
    if a0 == nil or a1 == nil then return nil, "waiting for constraint attachments" end
    local p0 = directAttachmentPart(a0)
    local p1 = directAttachmentPart(a1)
    if p0 == nil or p1 == nil then
        return nil, "constraint endpoints must be Attachments directly inside BaseParts (Bone not supported)"
    end

    local root = opts.Root
    local part = opts.Tail
    if root == nil and part == nil then
        if p0:FindFirstAncestorOfClass("Accessory") and not p1:FindFirstAncestorOfClass("Accessory") then
            root, part = p1, p0
        elseif p1:FindFirstAncestorOfClass("Accessory") and not p0:FindFirstAncestorOfClass("Accessory") then
            root, part = p0, p1
        else
            return nil, "specify Root and Tail for non-accessory rigid constraints"
        end
    elseif root == nil then
        root = if part == p0 then p1 else p0
    elseif not part then
        part = if root == p0 then p1 else p0
    end
    assert(root ~= nil and part ~= nil, "missing Root/Tail")
    assert(root ~= part and (root == p0 or root == p1) and (part == p0 or part == p1),
        "TuxPhysicsTails: Root and Tail must match the constraint's attached parts")
    local alreadyRegistered = byPart[part]
    if alreadyRegistered then
        if alreadyRegistered.SourceConstraint == constraint then
            return alreadyRegistered :: Controller, nil
        end
        return nil, "tail already registered"
    end
    if part.Anchored then return nil, "tail part is anchored" end
    if not constraint.Enabled then return nil, "source constraint is disabled" end

    local rootAttachment = if a0.Parent == root then a0 else a1
    local tailAttachment = if a0.Parent == part then a0 else a1
    local originalEnabled = constraint.Enabled

    -- Every offset comes from the source attachment, not from the Handle
    -- CFrame or imported MeshPart's unusual pivot.
    local joint = Instance.new("Weld")
    joint.Name = "TuxPhysicsTails_VisualWeld"
    joint.Part0 = root
    joint.Part1 = part
    joint.C0 = rootAttachment.CFrame
    joint.C1 = tailAttachment.CFrame

    -- Both operations are client-local. Existing constraint attachment
    -- instances are NEVER modified, cloned, or reparented.
    constraint.Enabled = false
    joint.Parent = part
    local ok, result = pcall(function(): Internal
		assert(root, "Root must be a BasePart.")
		assert(part, "Part must be a BasePart.")
        return buildController(joint, root, part, opts, true,
            constraint, rootAttachment, tailAttachment, originalEnabled, rootAttachment.CFrame)
    end)
    if not ok then
        joint:Destroy()
        if constraint.Parent then constraint.Enabled = originalEnabled end
        error(result, 2)
    end
    return result :: Controller, nil
end

function Engine.Attach(part: BasePart, root: BasePart, options: Registration?): Controller
    assert(part:IsA("BasePart") and root:IsA("BasePart"), "TuxPhysicsTails: expected BaseParts")
    assert(root ~= part and not part.Anchored, "TuxPhysicsTails: tail must be a different unanchored part")
    assert(byPart[part] == nil, "TuxPhysicsTails: part already registered")
    local opts: Registration = options or {}
    validateRegistration(opts)
    local rest = root.CFrame:ToObjectSpace(part.CFrame)
    local half = root.Size * 0.5
    local p = rest.Position
    local auto = CFrame.new(
        math.clamp(p.X, -half.X, half.X),
        math.clamp(p.Y, -half.Y, half.Y),
        math.clamp(p.Z, -half.Z, half.Z)
    )
    local joint = Instance.new("Weld")
    joint.Name = "TuxPhysicsTails_VisualWeld"
    joint.Part0 = root
    joint.Part1 = part
    joint.C0 = rest
    joint.C1 = CFrame.identity
    joint.Parent = part
    local ok, result = pcall(function(): Internal
        return buildController(joint, root, part, opts, true, nil, nil, nil, nil, auto)
    end)
    if not ok then
        joint:Destroy()
        error(result, 2)
    end
    return result :: Controller
end

function Engine.RegisterAccessory(accessory: Accessory, options: Registration?): (Controller?, string?)
    assert(accessory:IsA("Accessory"), "TuxPhysicsTails: expected Accessory")
    local existing = byAccessory[accessory]
    if existing then return existing :: Controller, nil end
    local handle = accessory:FindFirstChild("Handle")
    if handle == nil or not handle:IsA("BasePart") then return nil, "waiting for Handle" end
    local opts: Registration = table.clone(options or {} :: Registration)
    opts.Accessory = accessory
    opts.Tail = handle
    -- Prefer the modern constraint if present. During the avatar joint
    -- upgrade, the constraint may appear *after* a legacy weld is removed.
    local rigid = handle:FindFirstChild("AccessoryRigidConstraint", true)
    if rigid and rigid:IsA("RigidConstraint") then
        if rigid.Attachment0 == nil or rigid.Attachment1 == nil then
            return nil, "waiting for AccessoryRigidConstraint endpoints"
        end
        return Engine.RegisterRigidConstraint(rigid, opts)
    end
    local foundWeld: Instance? = handle:FindFirstChild("AccessoryWeld", true)
    local legacy: Joint? = nil
    if foundWeld ~= nil then
        if foundWeld:IsA("Weld") then
            legacy = foundWeld
        elseif foundWeld:IsA("ManualWeld") then
            legacy = foundWeld
        end
    end
    if legacy ~= nil then
        if legacy.Part0 == nil or legacy.Part1 == nil then
            return nil, "waiting for weld parts"
        end
        return Engine.RegisterWeld(legacy, opts), nil
    end
    return nil, "waiting for AccessoryRigidConstraint or AccessoryWeld"
end

function Engine.SetDefaults(patch: OptionPatch): ()
    validateOptions(patch)
    defaultOptions = mergeOptions(defaultOptions, patch)
    for _, item in ipairs(tails) do
        item._options = currentOptions(item._overrides)
        if patch.AxisFrame ~= nil or patch.MassOffset ~= nil or patch.ScaleWithCharacter ~= nil then
            item:_recomputeGeometry()
            item:Reset()
        end
    end
end

function Engine.GetDefaults(): Options
    return table.clone(defaultOptions)
end

function Engine.GetConfiguration(): Configuration
    local copy = table.clone(settings)
    copy.IncludedAccessoryNames = table.clone(settings.IncludedAccessoryNames)
    return copy
end

local function filterPark(item: Internal): ()
    if not settings.Enabled or not item.Enabled then
        item:_park()
        return
    end
    if item.Accessory and ignoredAccessories[item.Accessory] then
        item:_park()
        return
    end
    if item.Character then
        if ignoredCharacters[item.Character] then
            item:_park()
            return
        end
        local player = Players:GetPlayerFromCharacter(item.Character)
        if player and ignoredPlayers[player] then item:_park() end
    end
end

function Engine.Configure(patch: ConfigurationPatch): ()
    validateConfiguration(patch)
    settings = mergeConfiguration(settings, patch)
    settings.IncludedAccessoryNames = table.clone(settings.IncludedAccessoryNames)
    if patch.IncludedAccessoryNames ~= nil then rebuildNames() end
    if patch.Enabled == false then
        for _, item in ipairs(tails) do item:_park() end
    end
    -- Changing AutoPlayers while running is supported by restarting the
    -- player watchers. The render connection and existing controllers remain.
    if patch.AutoPlayers ~= nil and running then
        if settings.AutoPlayers then
            for _, player in ipairs(Players:GetPlayers()) do
                Engine.WatchPlayer(player)
            end
        else
            for player, connection in pairs(playerWatches) do
                connection:Disconnect()
                playerWatches[player] = nil
            end
        end
    end
end

function Engine.SetEnabled(enabled: boolean): ()
    Engine.Configure({ Enabled = enabled })
end

function Engine.SetPlayerEnabled(player: Player, enabled: boolean): ()
    assert(player:IsA("Player") and type(enabled) == "boolean", "TuxPhysicsTails: invalid player filter")
    if enabled then
        ignoredPlayers[player] = nil
    else
        ignoredPlayers[player] = true
    end
    if not enabled then
        for _, item in ipairs(tails) do
            if item.Character == player.Character then item:_park() end
        end
    end
end

function Engine.SetCharacterEnabled(character: Model, enabled: boolean): ()
    assert(character:IsA("Model") and type(enabled) == "boolean", "TuxPhysicsTails: invalid character filter")
    if enabled then
        ignoredCharacters[character] = nil
    else
        ignoredCharacters[character] = true
    end
    if not enabled then
        for _, item in ipairs(tails) do
            if item.Character == character then item:_park() end
        end
    end
end

function Engine.SetAccessoryEnabled(accessory: Accessory, enabled: boolean): ()
    assert(accessory:IsA("Accessory") and type(enabled) == "boolean", "TuxPhysicsTails: invalid accessory filter")
    if enabled then
        ignoredAccessories[accessory] = nil
    else
        ignoredAccessories[accessory] = true
    end
    if not enabled then
        local item = byAccessory[accessory]
        if item then item:_park() end
    end
end

function Engine.AddIncludedName(name: string): ()
    assert(type(name) == "string", "TuxPhysicsTails: expected string")
    if includeNames[string.lower(name)] then return end
    table.insert(settings.IncludedAccessoryNames, name)
    rebuildNames()
end

function Engine.RemoveIncludedName(name: string): ()
    assert(type(name) == "string", "TuxPhysicsTails: expected string")
    for i = #settings.IncludedAccessoryNames, 1, -1 do
        if string.lower(settings.IncludedAccessoryNames[i]) == string.lower(name) then
            table.remove(settings.IncludedAccessoryNames, i)
        end
    end
    rebuildNames()
end

function Engine.IsRecognizedAccessory(accessory: Accessory): boolean
    if not settings.AutoDetect or ignoredAccessories[accessory] then return false end
    local name = string.lower(accessory.Name)
    -- Explicit inclusion is authoritative even for unconventional accessory
    -- types; the Back/Waist filter only applies to heuristic detection.
    if includeNames[name] then return true end
    if settings.RequireAccessoryType then
        local category = accessory.AccessoryType
        if category ~= Enum.AccessoryType.Back and category ~= Enum.AccessoryType.Waist then return false end
    end
    return settings.NameKeyword ~= ""
        and string.find(name, string.lower(settings.NameKeyword), 1, true) ~= nil
end

local function stopAccessoryWatch(accessory: Accessory): ()
    local watch = accessoryWatches[accessory]
    if not watch then return end
    accessoryWatches[accessory] = nil
    for _, connection in ipairs(watch.Connections) do connection:Disconnect() end
    for _, connection in ipairs(watch.JointConnections) do connection:Disconnect() end
end

local function watchAccessory(character: Model, accessory: Accessory): ()
    if accessoryWatches[accessory] then return end
    if not Engine.IsRecognizedAccessory(accessory) then return end

    local watch: AccessoryWatch = {
        Character = character,
        Connections = {},
        JointConnections = {},
        TryRegister = function() end,
    }
    accessoryWatches[accessory] = watch
    local function clearJointListeners()
        for _, connection in ipairs(watch.JointConnections) do connection:Disconnect() end
        table.clear(watch.JointConnections)
    end
    local previousWarning: string? = nil
    local function tryRegister()
        if not running or not accessory:IsDescendantOf(character) then
            stopAccessoryWatch(accessory)
            return
        end
        if byAccessory[accessory] then return end
        local ok, outcome = pcall(function(): { Controller: Controller?, Reason: string? }
            local controller, reason = Engine.RegisterAccessory(accessory, { Character = character })
            return { Controller = controller, Reason = reason }
        end)
        if not ok then
            local message = tostring(outcome)
            if message ~= previousWarning then
                previousWarning = message
                warn("TuxPhysicsTails: could not register '" .. accessory.Name .. "': " .. message)
            end
            return
        end
        local response = outcome :: { Controller: Controller?, Reason: string? }
        if response.Controller ~= nil then return end
        local reason = response.Reason
        -- Endpoints can be assigned asynchronously during character loading.
        if reason ~= nil and string.find(reason, "waiting", 1, true) then
            local handle = accessory:FindFirstChild("Handle")
            if handle then
                local joint = handle:FindFirstChild("AccessoryRigidConstraint", true)
                    or handle:FindFirstChild("AccessoryWeld", true)
                if joint then
                    clearJointListeners()
                    if joint:IsA("RigidConstraint") then
                        table.insert(watch.JointConnections, joint:GetPropertyChangedSignal("Attachment0"):Connect(tryRegister))
                        table.insert(watch.JointConnections, joint:GetPropertyChangedSignal("Attachment1"):Connect(tryRegister))
                    elseif joint:IsA("Weld") or joint:IsA("ManualWeld") then
                        table.insert(watch.JointConnections, joint:GetPropertyChangedSignal("Part0"):Connect(tryRegister))
                        table.insert(watch.JointConnections, joint:GetPropertyChangedSignal("Part1"):Connect(tryRegister))
                    end
                end
            end
        end
    end
    watch.TryRegister = tryRegister
    table.insert(watch.Connections, accessory.DescendantAdded:Connect(function()
        -- Roblox can replace AccessoryWeld with AccessoryRigidConstraint
        -- after a model enters Workspace; defer until the new joint is ready.
        task.defer(tryRegister)
    end))
    table.insert(watch.Connections, accessory.DescendantRemoving:Connect(function()
        task.defer(tryRegister)
    end))
    table.insert(watch.Connections, accessory.AncestryChanged:Connect(function()
        if not accessory:IsDescendantOf(character) then stopAccessoryWatch(accessory) end
    end))
    tryRegister()
end

local function stopCharacterWatch(character: Model): ()
    local connections = characterWatches[character]
    if not connections then return end
    characterWatches[character] = nil
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for accessory, watch in pairs(accessoryWatches) do
        if watch.Character == character then stopAccessoryWatch(accessory) end
    end
end

function Engine.ScanCharacter(character: Model): number
    assert(character:IsA("Model"), "TuxPhysicsTails: ScanCharacter expects Model")
    local added = 0
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory") and Engine.IsRecognizedAccessory(child) then
            if not byAccessory[child] then
                local ok, outcome = pcall(function(): { Controller: Controller?, Reason: string? }
                    local controller, reason = Engine.RegisterAccessory(child, { Character = character })
                    return { Controller = controller, Reason = reason }
                end)
                if ok then
                    local response = outcome :: { Controller: Controller?, Reason: string? }
                    if response.Controller ~= nil then
                        added += 1
                    end
                else
                    warn("TuxPhysicsTails: unable to register " .. child.Name .. ": " .. tostring(outcome))
                end
            end
            if running then watchAccessory(character, child) end
        end
    end
    return added
end

local function watchCharacter(character: Model): ()
    if characterWatches[character] then return end
    local c: { RBXScriptConnection } = {}
    characterWatches[character] = c
    table.insert(c, character.ChildAdded:Connect(function(child)
        if child:IsA("Accessory") then watchAccessory(character, child) end
    end))
    table.insert(c, character.AncestryChanged:Connect(function()
        if character.Parent == nil then stopCharacterWatch(character) end
    end))
    Engine.ScanCharacter(character)
end

function Engine.WatchPlayer(player: Player): ()
    if playerWatches[player] then return end
    playerWatches[player] = player.CharacterAdded:Connect(function(character)
        if settings.AutoPlayers then watchCharacter(character) end
    end)
    if settings.AutoPlayers and player.Character then watchCharacter(player.Character) end
end

function Engine.AddCharacterContainer(container: Instance): ()
    assert(typeof(container) == "Instance", "TuxPhysicsTails: expected Instance")
    if containerWatches[container] then return end
    local connections: { RBXScriptConnection } = {}
    containerWatches[container] = connections
    local function inspect(node: Instance)
        if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
            watchCharacter(node)
        elseif node:IsA("Humanoid") and node.Parent and node.Parent:IsA("Model") then
            watchCharacter(node.Parent)
        end
    end
    inspect(container)
    for _, node in ipairs(container:GetDescendants()) do inspect(node) end
    table.insert(connections, container.DescendantAdded:Connect(inspect))
end

function Engine.RemoveCharacterContainer(container: Instance): ()
    local connections = containerWatches[container]
    if not connections then return end
    containerWatches[container] = nil
    for _, connection in ipairs(connections) do connection:Disconnect() end
end

function Engine.GetStats(): Stats
    local active = 0
    for _, item in ipairs(tails) do
        if item._awake then active += 1 end
    end
    return { Registered = #tails, Simulating = active, Running = running }
end

local candidates: { Internal } = {}
local function nearer(a: Internal, b: Internal): boolean
    return a._distanceSquared < b._distanceSquared
end

local function update(dt: number): ()
    table.clear(candidates)
    local camera = workspace.CurrentCamera
    local cameraPos = if camera then camera.CFrame.Position else Vector3.zero
    local distanceLimit = settings.MaxDistance * settings.MaxDistance
    for i = #tails, 1, -1 do
        local item = tails[i]
        if item.Joint.Parent == nil or item.Root.Parent == nil or item.Part.Parent == nil then
            item:Destroy()
        elseif item.SourceConstraint and item.SourceConstraint.Parent == nil then
            item:Destroy()
        else
            filterPark(item)
            local allowed = settings.Enabled and item.Enabled
                and not (item.Accessory and ignoredAccessories[item.Accessory])
                and not (item.Character and ignoredCharacters[item.Character])
            if allowed and item.Character then
                local player = Players:GetPlayerFromCharacter(item.Character)
                if player and ignoredPlayers[player] then allowed = false end
            end
            if allowed then
                local d2 = if camera then (item.Root.Position - cameraPos).Magnitude ^ 2 else 0
                if d2 <= distanceLimit then
                    item._distanceSquared = d2
                    table.insert(candidates, item)
                else
                    item:_park()
                end
            end
        end
    end
    local budget = math.floor(settings.MaxVisibleTails)
    if #candidates > budget then
        table.sort(candidates, nearer)
        for i = budget + 1, #candidates do candidates[i]:_park() end
    end
    for i = 1, math.min(#candidates, budget) do candidates[i]:_step(dt) end
end

function Engine.Start(configuration: ConfigurationPatch?): ()
    assert(RunService:IsClient(), "TuxPhysicsTails: must Start() from a LocalScript")
    if configuration then Engine.Configure(configuration) end
    if running then return end
    running = true
    renderConnection = RunService.PreRender:Connect(update)
    table.insert(sharedConnections, Players.PlayerAdded:Connect(function(player)
        if settings.AutoPlayers then Engine.WatchPlayer(player) end
    end))
    table.insert(sharedConnections, Players.PlayerRemoving:Connect(function(player)
        local c = playerWatches[player]
        if c then c:Disconnect() end
        playerWatches[player] = nil
        ignoredPlayers[player] = nil
    end))
    if settings.AutoPlayers then
        for _, player in ipairs(Players:GetPlayers()) do Engine.WatchPlayer(player) end
    end
end

function Engine.Stop(): ()
    if not running then return end
    running = false
    if renderConnection then renderConnection:Disconnect() end
    renderConnection = nil
    for _, connection in ipairs(sharedConnections) do connection:Disconnect() end
    table.clear(sharedConnections)
    for player, connection in pairs(playerWatches) do
        connection:Disconnect()
        playerWatches[player] = nil
    end
    for character in pairs(characterWatches) do stopCharacterWatch(character) end
    for accessory in pairs(accessoryWatches) do stopAccessoryWatch(accessory) end
    for container in pairs(containerWatches) do Engine.RemoveCharacterContainer(container) end
    while #tails > 0 do tails[#tails]:Destroy() end
end

return Engine
