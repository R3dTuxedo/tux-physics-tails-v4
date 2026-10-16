--!strict
-- Example only. Do not paste into your game without defining tailPart and rootPart.
local Tails = require(game.ReplicatedStorage:WaitForChild("TuxPhysicsTails"))

local function attachCustomTail(tailPart: BasePart, rootPart: BasePart)
    local candidate = tailPart:FindFirstChild("TailTip", true)
    local tip: Attachment? = if candidate and candidate:IsA("Attachment") then candidate else nil
    local controller = Tails.Attach(tailPart, rootPart, {
        -- Body attachment point, not imported MeshPart pivot.
        Pivot = CFrame.new(0, -0.4, rootPart.Size.Z * 0.5),
        TipAttachment = tip,
        Frequency = 2.8,
        DampingRatio = 0.72,
        MaxAngle = math.rad(35),
        WagEnabled = true,
    })
    return controller
end

return attachCustomTail
