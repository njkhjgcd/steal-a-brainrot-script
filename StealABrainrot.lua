--=====================================================
-- Steal a Brainrot Hub - for Delta Executor (Mobile/PC)
-- Game: Steal a Brainrot | PlaceId: 109983668079237
-- No key, no external UI library - everything is built in
-- How to use: paste this whole file in Delta and Execute
--=====================================================

if _G.SABHubRunning then
    _G.SABHubRunning = false
    task.wait(0.3)
end
_G.SABHubRunning = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local function getChar()
    return LocalPlayer and LocalPlayer.Character
end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = getChar()
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

-- Settings
local S = {
    Speed = false, SpeedValue = 32,
    Jump = false, JumpValue = 80,
    Fly = false, FlySpeed = 50,
    Noclip = false,
    InfJump = false,
    InstantPrompt = false,
    PlayerESP = false,
    BrainrotESP = false,
    AutoCollect = false,
    AutoLock = false,
    AntiRagdoll = false,
    StealBoost = false,
}
getgenv().SABSettings = S

local function notify(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "SAB Hub", Text = tostring(text), Duration = 3
        })
    end)
    print("[SAB Hub] " .. tostring(text))
end

--=====================================================
-- Find my base / plot
-- The game organises bases in different folders depending
-- on the version, so we try several known heuristics.
--=====================================================
local function findMyBase()
    local candidates = {}
    for _, name in ipairs({"Plots", "Bases", "PlayerBases", "Tycoons", "Lots"}) do
        local f = Workspace:FindFirstChild(name)
        if f then table.insert(candidates, f) end
    end
    table.insert(candidates, Workspace)

    for _, parent in ipairs(candidates) do
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("Model") or obj:IsA("Folder") then
                local owner = obj:GetAttribute("Owner") or obj:GetAttribute("OwnerName") or obj:GetAttribute("Player")
                if owner and (tostring(owner) == LocalPlayer.Name or tostring(owner) == tostring(LocalPlayer.UserId)) then
                    return obj
                end
                local ov = obj:FindFirstChild("Owner", true)
                if ov and ov:IsA("ObjectValue") and ov.Value == LocalPlayer then return obj end
                if ov and (ov:IsA("StringValue") or ov:IsA("IntValue")) and (tostring(ov.Value) == LocalPlayer.Name or tostring(ov.Value) == tostring(LocalPlayer.UserId)) then
                    return obj
                end
                if string.find(string.lower(obj.Name), string.lower(LocalPlayer.Name)) then
                    return obj
                end
            end
        end
    end
    return nil
end

local function getBaseCFrame()
    local base = findMyBase()
    if not base then return nil end
    if base:IsA("Model") and base.PrimaryPart then return base:GetPivot() end
    local part = base:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.CFrame + Vector3.new(0, 5, 0) end
    return nil
end

--=====================================================
-- ProximityPrompt helpers
--=====================================================
local function allPrompts()
    local list = {}
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") then table.insert(list, v) end
    end
    return list
end

local function promptText(p)
    return string.lower((p.ActionText or "") .. " " .. (p.ObjectText or "") .. " " .. p.Name)
end

local function firePrompt(p)
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(p)
        else
            p.HoldDuration = 0
            p:InputHoldBegin()
            task.wait(0.05)
            p:InputHoldEnd()
        end
    end)
end

--=====================================================
-- GUI
--=====================================================
local guiParent = nil
pcall(function() guiParent = gethui and gethui() end)
if not guiParent then guiParent = game:GetService("CoreGui") end
pcall(function() if not guiParent then guiParent = LocalPlayer:WaitForChild("PlayerGui") end end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SABHubGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = guiParent

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 300, 0, 380)
Main.Position = UDim2.new(0.5, -150, 0.5, -190)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -70, 0, 36)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🧠  Steal a Brainrot Hub"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -64, 0, 4)
MinBtn.Text = "-"
MinBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 16
MinBtn.Parent = Main
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -32, 0, 4)
CloseBtn.Text = "X"
CloseBtn.BackgroundColor3 = Color3.fromRGB(170, 40, 40)
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.Parent = Main
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local Body = Instance.new("ScrollingFrame")
Body.Size = UDim2.new(1, -16, 1, -48)
Body.Position = UDim2.new(0, 8, 0, 42)
Body.BackgroundTransparency = 1
Body.ScrollBarThickness = 3
Body.CanvasSize = UDim2.new(0, 0, 0, 0)
Body.AutomaticCanvasSize = Enum.AutomaticSize.Y
Body.Parent = Main
local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 6)
Layout.Parent = Body

local function addLabel(text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 22)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(255, 200, 80)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = Body
    return l
end

local function addToggle(text, key, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.Text = "  " .. text .. " : OFF"
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = Body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        S[key] = not S[key]
        b.Text = "  " .. text .. (S[key] and " : ON" or " : OFF")
        b.BackgroundColor3 = S[key] and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(35, 35, 45)
        if callback then pcall(callback, S[key]) end
    end)
    return b
end

local function addSlider(text, key, minv, maxv, default)
    S[key] = default
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 44)
    holder.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    holder.Parent = Body
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -10, 0, 20)
    l.Position = UDim2.new(0, 8, 0, 2)
    l.BackgroundTransparency = 1
    l.Text = text .. " : " .. default
    l.TextColor3 = Color3.fromRGB(255, 255, 255)
    l.Font = Enum.Font.Gotham
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = holder
    local minus = Instance.new("TextButton")
    minus.Size = UDim2.new(0, 40, 0, 20)
    minus.Position = UDim2.new(0, 8, 0, 22)
    minus.Text = "-"
    minus.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
    minus.TextColor3 = Color3.fromRGB(255, 255, 255)
    minus.Parent = holder
    local plus = Instance.new("TextButton")
    plus.Size = UDim2.new(0, 40, 0, 20)
    plus.Position = UDim2.new(0, 54, 0, 22)
    plus.Text = "+"
    plus.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
    plus.TextColor3 = Color3.fromRGB(255, 255, 255)
    plus.Parent = holder
    local function upd()
        l.Text = text .. " : " .. S[key]
    end
    minus.MouseButton1Click:Connect(function()
        S[key] = math.max(minv, S[key] - 5) upd()
    end)
    plus.MouseButton1Click:Connect(function()
        S[key] = math.min(maxv, S[key] + 5) upd()
    end)
    return holder
end

local function addButton(text, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(50, 80, 140)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = text
    b.Parent = Body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function() pcall(callback) end)
    return b
end

--=====================================================
-- Menu items
--=====================================================
addLabel("— Main —")
addToggle("Speed Boost (when stealing)", "StealBoost")
addToggle("WalkSpeed", "Speed")
addSlider("WalkSpeed Value", "SpeedValue", 16, 150, 32)
addToggle("JumpPower", "Jump")
addSlider("JumpPower Value", "JumpValue", 50, 250, 80)
addToggle("Fly", "Fly")
addSlider("Fly Speed", "FlySpeed", 10, 200, 50)
addToggle("Noclip", "Noclip")
addToggle("Infinite Jump", "InfJump")
addToggle("Anti Ragdoll", "AntiRagdoll")

addLabel("— Steal / Base —")
addToggle("Instant Prompt (no hold)", "InstantPrompt")
addToggle("Auto Collect Cash", "AutoCollect")
addToggle("Auto Lock Base", "AutoLock")
addButton("Teleport to My Base", function()
    local cf = getBaseCFrame()
    local root = getRoot()
    if cf and root then
        root.CFrame = cf
        notify("Teleported to base")
    else
        notify("Base not found - walk near your base once and try again")
    end
end)

addLabel("— ESP —")
addToggle("Player ESP", "PlayerESP")
addToggle("Brainrot ESP", "BrainrotESP")

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Body.Visible = not minimized
    Main.Size = minimized and UDim2.new(0, 300, 0, 40) or UDim2.new(0, 300, 0, 380)
    MinBtn.Text = minimized and "+" or "-"
end)
CloseBtn.MouseButton1Click:Connect(function()
    _G.SABHubRunning = false
    ScreenGui:Destroy()
end)

notify("SAB Hub loaded - Steal a Brainrot")

--=====================================================
-- Logic loops
--=====================================================

-- Speed / Jump
task.spawn(function()
    while _G.SABHubRunning do
        local hum = getHum()
        if hum then
            if S.Speed then
                hum.WalkSpeed = S.SpeedValue
            elseif S.StealBoost then
                -- Boost only a bit above default while the toggle is on,
                -- useful to run a stolen brainrot back home faster.
                if hum.WalkSpeed < 40 then hum.WalkSpeed = 40 end
            end
            if S.Jump then
                hum.UseJumpPower = true
                hum.JumpPower = S.JumpValue
            end
            if S.AntiRagdoll then
                pcall(function()
                    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                    if hum:GetState() == Enum.HumanoidStateType.FallingDown then
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end)
            end
        end
        task.wait(0.15)
    end
end)

-- Noclip
RunService.Stepped:Connect(function()
    if S.Noclip and _G.SABHubRunning then
        local c = getChar()
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if S.InfJump and _G.SABHubRunning then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- Fly (works with mobile joystick + camera direction)
local flyBV, flyBG = nil, nil
task.spawn(function()
    while _G.SABHubRunning do
        local root = getRoot()
        local hum = getHum()
        if S.Fly and root and hum then
            if not flyBV then
                flyBV = Instance.new("BodyVelocity")
                flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                flyBV.Parent = root
                flyBG = Instance.new("BodyGyro")
                flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                flyBG.P = 9e4
                flyBG.Parent = root
            end
            local cam = Workspace.CurrentCamera
            flyBG.CFrame = cam.CFrame
            flyBV.Velocity = hum.MoveDirection * S.FlySpeed + Vector3.new(0, hum.Jump and 20 or 0, 0)
            hum.PlatformStand = false
        else
            if flyBV then flyBV:Destroy() flyBV = nil end
            if flyBG then flyBG:Destroy() flyBG = nil end
        end
        task.wait(0.05)
    end
    if flyBV then flyBV:Destroy() end
    if flyBG then flyBG:Destroy() end
end)

-- Instant Prompt: set every prompt's HoldDuration to 0
task.spawn(function()
    while _G.SABHubRunning do
        if S.InstantPrompt then
            for _, p in ipairs(allPrompts()) do
                pcall(function() p.HoldDuration = 0 end)
            end
        end
        task.wait(1)
    end
end)

-- Auto Collect + Auto Lock: fire matching prompts inside MY base only
task.spawn(function()
    while _G.SABHubRunning do
        if S.AutoCollect or S.AutoLock then
            local base = findMyBase()
            local root = getRoot()
            if base and root then
                for _, p in ipairs(base:GetDescendants()) do
                    if p:IsA("ProximityPrompt") then
                        local t = promptText(p)
                        if S.AutoCollect and (string.find(t, "collect") or string.find(t, "cash")) then
                            firePrompt(p)
                        end
                        if S.AutoLock and string.find(t, "lock") then
                            firePrompt(p)
                        end
                    end
                end
            end
        end
        task.wait(2)
    end
end)

--=====================================================
-- ESP
--=====================================================
local espFolder = Instance.new("Folder")
espFolder.Name = "SAB_ESP"
espFolder.Parent = ScreenGui

local function makeBillboard(target, text, color)
    local gui = Instance.new("BillboardGui")
    gui.Name = "SAB_ESP_TAG"
    gui.Size = UDim2.new(0, 160, 0, 36)
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.AlwaysOnTop = true
    gui.Adornee = target
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color
    l.Font = Enum.Font.GothamBold
    l.TextSize = 13
    l.TextStrokeTransparency = 0.4
    l.Parent = gui
    gui.Parent = espFolder
    return gui
end

local playerTags = {}
local brainrotTags = {}

task.spawn(function()
    while _G.SABHubRunning do
        -- Player ESP
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local root = plr.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    if S.PlayerESP and not playerTags[plr] then
                        local hl = Instance.new("Highlight")
                        hl.Name = "SAB_ESP_HL"
                        hl.FillColor = Color3.fromRGB(255, 60, 60)
                        hl.FillTransparency = 0.5
                        hl.Parent = plr.Character
                        playerTags[plr] = {hl = hl, tag = makeBillboard(root, plr.DisplayName, Color3.fromRGB(255, 90, 90))}
                    elseif not S.PlayerESP and playerTags[plr] then
                        if playerTags[plr].hl then playerTags[plr].hl:Destroy() end
                        if playerTags[plr].tag then playerTags[plr].tag:Destroy() end
                        playerTags[plr] = nil
                    end
                end
            end
        end

        -- Brainrot ESP: models that carry a ProximityPrompt are the
        -- interactable brainrots in bases and on the conveyor.
        if S.BrainrotESP then
            local seen = {}
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("ProximityPrompt") then
                    local model = v:FindFirstAncestorOfClass("Model")
                    if model and model ~= getChar() then
                        local part = v.Parent
                        if part and part:IsA("BasePart") and not brainrotTags[model] and not seen[model] then
                            seen[model] = true
                            local label = v.ObjectText ~= "" and v.ObjectText or model.Name
                            brainrotTags[model] = makeBillboard(part, "🧠 " .. label, Color3.fromRGB(120, 255, 140))
                        end
                    end
                end
            end
        else
            for m, tag in pairs(brainrotTags) do
                if tag then tag:Destroy() end
                brainrotTags[m] = nil
            end
        end
        task.wait(2)
    end
    -- cleanup
    for _, d in pairs(playerTags) do
        if d.hl then d.hl:Destroy() end
        if d.tag then d.tag:Destroy() end
    end
    for _, tag in pairs(brainrotTags) do if tag then tag:Destroy() end end
end)
