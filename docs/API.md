# Tux Physics Tails — API reference

Version **4.2** · `--!strict` Luau · All API calls are **client-side** unless specifically stated otherwise.

```luau
local Tails = require(game:GetService("ReplicatedStorage").TuxPhysicsTails)
local Types = require(game:GetService("ReplicatedStorage").TuxPhysicsTails.Types)
type Controller = Types.Controller
type Registration = Types.Registration
type OptionPatch = Types.OptionPatch
```

The included `TuxPhysicsTailsClient` LocalScript calls `Tails.Start()` automatically. All engine functions use dot syntax (`Tails.Attach(...)`); controller functions use colon syntax (`controller:SetOptions(...)`). The engine's public `GetDefaults()`, `GetOptions()`, and `GetConfiguration()` methods return copies that can be read without mutating engine state.

## Lifecycle and global configuration

### `Tails.Start(configuration: ConfigurationPatch?): ()`
Starts one local `PreRender` animation loop, initializes player watches, and optionally applies a configuration patch first. Calling repeatedly while running is safe and does not create duplicate loops. The included LocalScript already invokes this.

### `Tails.Stop(): ()`
Stops the render loop and all watches, removes every registered controller, and restores source joints/constraints when they are still present. Calling repeatedly is safe. Can be followed by `Start()`.

### `Tails.Configure(patch: ConfigurationPatch): ()`
Updates global engine/detection/performance settings. Unspecified properties retain their previous values.

### `Tails.GetConfiguration(): Configuration`
Returns a copy of global settings, including a separately copied `IncludedAccessoryNames` array.

### `Tails.SetDefaults(patch: OptionPatch): ()`
Updates default tail physics settings. Existing controllers inherit modified defaults except where overridden via registration or `controller:SetOptions()`.

### `Tails.GetDefaults(): Options`
Returns the current complete default tail options.

### `Tails.SetEnabled(enabled: boolean): ()`
Enables/disables all registered tails on this client. Disabled tails return to rest; registration and watches are retained.

### `Tails.GetStats(): Stats`
Returns `{ Registered: number, Simulating: number, Running: boolean }`.

## Registering tails

### `Tails.Attach(part: BasePart, root: BasePart, options: Registration?): Controller`
Creates a private Weld between a loose, unanchored `part` and `root`, preserving the part's **current** rest pose. `Pivot` can override the inferred hinge. `controller:Destroy()` destroys this engine-owned weld.

### `Tails.RegisterWeld(joint: Weld | ManualWeld, options: Registration?): Controller`
Takes control of an existing Weld or ManualWeld. Pass `Root` and `Tail` when connection direction is ambiguous. Preserves/restores both original `C0` and `C1` and accepts reversed `Part0`/`Part1` ordering. Does **not** destroy an externally owned joint on cleanup.

### `Tails.RegisterRigidConstraint(constraint: RigidConstraint, options: Registration?): (Controller?, string?)`
Adapts a constraint connected to two attachments on BaseParts. Automatically detects which endpoint is the accessory handle when possible; otherwise specify `Root` and `Tail`. Disables the original constraint **locally**, creates its own Weld, and restores the constraint on removal. Returns `nil, reason` if a supported connection is not ready or possible. Endpoints on `Bone`s are unsupported.

### `Tails.RegisterAccessory(accessory: Accessory, options: Registration?): (Controller?, string?)`
Registers the accessory's `Handle`, preferring `AccessoryRigidConstraint`, falling back to `AccessoryWeld` (`Weld`/`ManualWeld`). Returns `nil, reason` if the Handle/joint has not loaded or a connection is unsupported. With automatic detection enabled, player characters are watched for late arrivals.

### `Tails.GetTail(value: Controller | Instance): Controller?`
Returns a controller for a registered controller instance, tail `BasePart`, source `Weld`/`ManualWeld`, `Accessory`, or source `RigidConstraint`. Returns `nil` if not registered.

### `Tails.Remove(value: Controller | Instance): boolean`
Removes a registered tail, restores externally owned joints/constraints where possible, and returns `true` on success; `false` if no matching controller exists.

## Discovery and inclusion

### `Tails.WatchPlayer(player: Player): ()`
Connects character/respawn detection for a player. Safe to call repeatedly for the same player.

### `Tails.ScanCharacter(character: Model): number`
Scans a character's existing children for known tail accessories; returns the count newly registered immediately. Accessories whose joints arrive later are also watched when the engine is running.

### `Tails.AddCharacterContainer(container: Instance): ()`
Watches an additional hierarchy for NPCs with Humanoids, and scans existing descendants. Repeated registration of the same container is ignored.

### `Tails.RemoveCharacterContainer(container: Instance): ()`
Disconnects automatic discovery for that container. Already created controllers are not implicitly destroyed; use `Remove()` or `Stop()` if necessary.

### `Tails.IsRecognizedAccessory(accessory: Accessory): boolean`
Checks inclusion/detection rules. Explicitly included accessory names bypass the Back/Waist accessory-type heuristic.

### `Tails.AddIncludedName(name: string): ()`
Adds an exact case-insensitive accessory-name inclusion (for accessories with names like `cube.003accessory`). Duplicates are ignored.

### `Tails.RemoveIncludedName(name: string): ()`
Removes case-insensitive matches from the explicit-name inclusion list.

## Individual client filters

### `Tails.SetPlayerEnabled(player: Player, enabled: boolean): ()`
Disables/re-enables simulation for a particular player's character **as seen by this client**. This does not disable their tail for other players.

### `Tails.SetCharacterEnabled(character: Model, enabled: boolean): ()`
Disables/re-enables a particular character (including NPCs) locally.

### `Tails.SetAccessoryEnabled(accessory: Accessory, enabled: boolean): ()`
Disables/re-enables a particular accessory locally.

## Controller methods

Controllers are returned by `Attach`, `RegisterWeld`, `RegisterRigidConstraint`, `RegisterAccessory` or `GetTail`.

### `controller:SetOptions(patch: OptionPatch): ()`
Changes one tail's physics. Unspecified overrides remain unchanged. `AxisFrame`, `MassOffset` or `ScaleWithCharacter` changes refresh geometry and reset the simulation.

### `controller:GetOptions(): Options`
Returns a complete copy of that tail's resolved settings.

### `controller:SetEnabled(enabled: boolean): ()`
Disables/enables only this controller; a disabled tail rests while remaining registered.

### `controller:SetPivot(pivot: CFrame | Attachment): ()`
Sets the rotation pivot. A `CFrame` is in **root-part local** coordinates. An `Attachment` on the root or tail can also be used; tail attachment frames are resolved relative to the captured rest pose.

### `controller:SetTip(tip: Vector3 | Attachment): ()`
Sets the approximate tip/mass influence point. A `Vector3` is in **tail-part local** coordinates; an attachment can be on either part. Enables more reliable torque calculation for oddly shaped meshes.

### `controller:Reset(): ()`
Clears spring/velocity state and restores the authored rest pose without unregistering.

### `controller:GetState(): State`
Returns `{ Enabled, Active, Angle, AngularVelocity, Pivot, Lever, Root, Part, Joint, SourceConstraint, Character, Accessory }`. `Angle` is a Vector3 of radians; `AngularVelocity` is radians per second. `Pivot`/`Lever` are expressed in root-part local coordinates.

### `controller:Destroy(): ()`
Unregisters this tail; equivalent to `Tails.Remove(controller)`.

## Tail options: `Types.Options` and `Types.OptionPatch`

`Options` is a complete record; `OptionPatch` contains the same keys as optional fields. **All angles are in radians** unless explicitly described otherwise.

| Name | Type | Default | Meaning |
| --- | --- | --- | --- |
| `Frequency` | `number` | `2.6` | Spring oscillation frequency (Hz) |
| `DampingRatio` | `number` | `0.72` | `<1` bouncy; `1` critically damped; `>1` overdamped |
| `TimeScale` | `number` | `1` | Scales spring and animation time; `0` pauses progress |
| `MaxAngle` | `number` | `math.rad(42)` | Maximum combined spring/wag angle magnitude |
| `LinearInfluence` | `Vector3` | `(0.003, 0.004, 0.003)` | Per-axis spring torque response to acceleration |
| `AngularInfluence` | `Vector3` | `(0.085, 0.12, 0.085)` | Per-axis response to turning velocity |
| `AngularAccelerationInfluence` | `Vector3` | `(0.006, 0.006, 0.006)` | Per-axis response to angular acceleration |
| `VelocitySmoothing` | `number` | `17` | Exponential velocity smoothing coefficient |
| `GravityScale` | `number` | `0.12` | Gravity difference multiplier; `0` disables it |
| **`NeutralGravity`** | `number` | **`196.2`** | Gravity at which the authored rest pose is neutral |
| `WindEnabled` | `boolean` | `true` | Include `workspace.GlobalWind` in the wind vector |
| `CustomWind` | `Vector3` | `Vector3.zero` | Additional world-space wind vector |
| `WindInfluence` | `number` | `1` | Scale the nonlinear fluctuating wind-pressure response; `0` disables it |
| `ExternalAcceleration` | `Vector3` | `Vector3.zero` | Extra world-space acceleration |
| `TeleportDistance` | `number` | `12` | Studs per frame beyond which input motion is treated as teleport |
| `TeleportAngle` | `number` | `math.rad(125)` | Rotation per frame beyond which input is treated as teleport |
| `WagEnabled` | `boolean` | `true` | Whether to apply idle wagging |
| `WagAmplitude` | `Vector3` | `(0.07, 0.16, 0.04)` | Per-axis wag angle amplitude in radians |
| `WagSpeed` | `number` | `1.8` | Wag cycles per second |
| `WagBlendSpeed` | `number` | `3.2` | Idle/moving blend transition speed |
| `WagMotionThreshold` | `number` | `3` | Motion activity threshold for fading wag |
| `AxisFrame` | `CFrame` | `CFrame.identity` | Custom physics axis rotation in root local space |
| `MassOffset` | `Vector3` | `Vector3.zero` | Approximate lever point in tail local space if no tip provided |
| `ScaleWithCharacter` | `boolean` | `false` | Optional avatar scaling of original *manual weld* offsets; use `false` for modern accessory constraints |

### Neutral gravity example

```luau
Tails.SetDefaults({
    GravityScale = 0.12,
    NeutralGravity = 196.2,
})
-- gravity = 196.2 -> delta = 0 -> no extra gravity torque
-- gravity = 296.2 -> delta = +100 -> downward-pressure response
-- gravity = 96.2  -> delta = -100 -> upward-pressure response
```

### Legacy gust example

```luau
Tails.SetDefaults({
    WindEnabled = true,                 -- workspace.GlobalWind contributes
    CustomWind = Vector3.new(3, 0, 0), -- additional constant breeze
    WindInfluence = 0.9,
})
```

`Wind.Sample(wind: Vector3, timeSeconds: number, influence: number): Vector3` is defined in `Wind.luau`. It uses the original oscillation terms (`sin(t*4)`, `sin(t*2)`, a nonlinear wind pressure term and strong-wind jitter). `Wag.Step(...)` is isolated in `Wag.luau`; modifying it is intentionally supported.

## Global configuration: `Types.Configuration` and `Types.ConfigurationPatch`

| Name | Type | Default | Meaning |
| --- | --- | --- | --- |
| `AutoPlayers` | `boolean` | `true` | Discover and watch players' characters |
| `AutoDetect` | `boolean` | `true` | Enable heuristic accessory detection |
| `RequireAccessoryType` | `boolean` | `true` | Require Back or Waist type for automatic name-based matching |
| `NameKeyword` | `string` | `"tail"` | Case-insensitive substring, empty string disables keyword detection |
| `IncludedAccessoryNames` | `{string}` | `{}` | Case-insensitive exact-name allow list |
| `Enabled` | `boolean` | `true` | Globally simulate/render tails on this client |
| `MaxDistance` | `number` | `240` | Max camera range in studs; `math.huge` disables range culling |
| `MaxVisibleTails` | `number` | `200` | Maximum nearest eligible controllers simulated per frame |
| `MaxFrameGap` | `number` | `0.15` | Frame gap beyond which physics resets rather than injecting impulses |

## Registration-only fields: `Types.Registration`

`Registration` is a *flat* optional record: it supports every `OptionPatch` property **plus** these registration-specific properties. It is not an intersection type, avoiding cyclic/optional-field inference issues in the Luau typechecker.

| Field | Type | Meaning |
| --- | --- | --- |
| `Root` | `BasePart?` | Which connected part should be the fixed/root-side part |
| `Tail` | `BasePart?` | Which connected part should swing |
| `Pivot` | `(CFrame | Attachment)?` | Authored hinge; CFrame uses root local space |
| `TipAttachment` | `(Vector3 | Attachment)?` | Tail local Vector3 or a real Attachment for force leverage |
| `Character` | `Model?` | Character owner; optional if inferable |
| `Accessory` | `Accessory?` | Accessory owner; automatically supplied by `RegisterAccessory()` |
| `Enabled` | `boolean?` | Initial controller enabled state (default `true`) |

## Low-level modules

| Module | Function | Notes |
| --- | --- | --- |
| `Spring` | `Spring.Step(position: Vector3, velocity: Vector3, target: Vector3, frequencyHz: number, dampingRatio: number, dt: number): (Vector3, Vector3)` | Closed-form damped spring solution |
| `Wind` | `Wind.Sample(wind: Vector3, timeSeconds: number, influence: number): Vector3` | Original Tux wind fluctuation |
| `Wag` | `Wag.NewState(phaseSeed: number): Wag.State` | Creates per-tail phase and blend state |
| `Wag` | `Wag.Reset(state: Wag.State): ()` | Clears fade state, preserves phase |
| `Wag` | `Wag.Step(state: Wag.State, dt: number, speed: number, amplitude: Vector3, blendSpeed: number, activity: number, motionThreshold: number): Vector3` | Returns procedural wag-angle offset |

## Notes

Only one controller may own a particular animated tail BasePart at a time. The rigid-constraint adapter does not support animated Bones or skinned tail deformation. Physics is a local visual effect and is not automatically synchronized between clients. Do not directly write to a joint managed by this engine unless you first call `Remove()` or `Destroy()`.
