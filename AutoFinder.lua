--=====================================================
-- Steal a Brainrot - AUTO FINDER for Delta Executor
-- Scans the current server for the best brainrot,
-- highlights + teleports to it, and (optional) server-hops
-- until a target at/above your rarity & income is found.
--
-- Rarity order (verified): Common < Rare < Epic < Legendary
--   < Mythic < Brainrot God < Secret < OG
--
-- Standalone use: paste in Delta and Execute.
-- It also auto-resumes after a server hop if it was ON,
-- as long as Delta's queue_on_teleport works.
--=====================================================

if _G.SABFinderRunning then
    _G.SABFinderRunning = false
    task.wait(0.3)
end
_G.SABFinderRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local FINDER_RAW = "https://raw.githubusercontent.com/njkhjgcd/steal-a-brainrot-script/main/AutoFinder.lua"
local SETTINGS_FILE = "SABFinder_Settings.json"
local VISITED_FILE = "SABFinder_Visited.json"

-- ---------- settings ----------
local RARITIES = {"Any", "Rare", "Epic", "Legendary", "Mythic", "Brainrot God", "Secret", "OG"}
local RARITY_SCORE = {["common"]=1, ["rare"]=2, ["epic"]=3, ["legendary"]=4, ["mythic"]=5, ["brainrot god"]=6, ["god"]=6, ["secret"]=7, ["og"]=8}
local INCOME_STEPS = {0, 1000, 10000, 20000, 100000, 325000, 1000000, 10000000, 100000000}

local F = {
    Enabled = false,
    MinRarityIdx = 6,      -- default: Brainrot God and above
    MinIncomeIdx = 1,      -- default: 0 (no minimum)
    AutoTeleport = true,
    AutoSteal = false,
    AutoHop = true,
    HopWaitSeconds = 15,   -- rescan this long in a server before hopping
}

local function saveSettings()
    pcall(function()
        if writefile then
            writefile(SETTINGS_FILE, HttpService:JSONEncode({
                Enabled = F.Enabled, MinRarityIdx = F.MinRarityIdx, MinIncomeIdx = F.MinIncomeIdx,
                AutoTeleport = F.AutoTeleport, AutoSteal = F.AutoSteal, AutoHop = F.AutoHop,
            }))
        end
    end)
end
local function loadSettings()
    pcall(function()
        if readfile and isfile and isfile(SETTINGS_FILE) then
            local d = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            for k, v in pairs(d) do F[k] = v end
        end
    end)
end
loadSettings()

-- ---------- helpers ----------
local function notify(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {Title = "Auto Finder", Text = tostring(text), Duration = 4})
    end)
    print("[AutoFinder] " .. tostring(text))
end

local function formatMoney(n)
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n))
end

local SUFFIX = {K = 1e3, M = 1e6, B = 1e9, T = 1e12}
local function parseIncome(text)
    if not text then return 0 end
    local clean = string.gsub(tostring(text), ",", "")
    -- look for a number (with optional suffix) followed by /s
    local num, suf = string.match(clean, "([%d%.]+)%s*([KMBT])%s*/s")
    if num then return (tonumber(num) or 0) * (SUFFIX[suf] or 1) end
    num = string.match(clean, "([%d%.]+)%s*/s")
    if num then return tonumber(num) or 0 end
    return 0
end

local function rarityFromText(text)
    if not text then return 0, nil end
    local low = string.lower(tostring(text))
    -- check longest names first so "brainrot god" wins over "god"
    if string.find(low, "brainrot god") then return 6, "Brainrot God" end
    for name, score in pairs(RARITY_SCORE) do
        if name ~= "god" and string.find(low, name, 1, true) then
            return score, name
        end
    end
    return 0, nil
end

local function getRoot()
    local c = LocalPlayer and LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ---------- brainrot scanning ----------
local function modelRootPart(model)
    return model:FindFirstChild("HumanoidRootPart", true)
        or model:FindFirstChild("RootPart", true)
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function inspectModel(model, prompt)
    if Players:GetPlayerFromCharacter(model) then return nil end
    if model == (LocalPlayer and LocalPlayer.Character) then return nil end
    local part = modelRootPart(model)
    if not part then return nil end

    local info = {model = model, part = part, prompt = prompt, name = model.Name, income = 0, rarityScore = 0, rarityName = "?"}

    if prompt and prompt.ObjectText and prompt.ObjectText ~= "" then
        info.name = prompt.ObjectText
    end

    -- attributes on the model itself
    pcall(function()
        for k, v in pairs(model:GetAttributes()) do
            local lk = string.lower(k)
            if type(v) == "number" and (string.find(lk, "generation") or string.find(lk, "income") or string.find(lk, "money") or string.find(lk, "cash") or string.find(lk, "persec") or string.find(lk, "cps")) then
                if v > info.income then info.income = v end
            elseif type(v) == "string" then
                local s, rn = rarityFromText(v)
                if s > info.rarityScore then info.rarityScore, info.rarityName = s, rn end
                local inc = parseIncome(v)
                if inc > info.income then info.income = inc end
            end
        end
    end)

    -- text labels + named values inside the model (the game shows
    -- name / rarity / $ per second on a billboard above each brainrot)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local inc = parseIncome(d.Text)
            if inc > info.income then info.income = inc end
            local s, rn = rarityFromText(d.Text)
            if s > info.rarityScore then info.rarityScore, info.rarityName = s, rn end
        elseif (d:IsA("NumberValue") or d:IsA("IntValue")) and type(d.Value) == "number" then
            local ln = string.lower(d.Name)
            if string.find(ln, "generation") or string.find(ln, "income") or string.find(ln, "money") or string.find(ln, "cash") then
                if d.Value > info.income then info.income = d.Value end
            end
        elseif d:IsA("StringValue") then
            local s, rn = rarityFromText(d.Value)
            if s > info.rarityScore then info.rarityScore, info.rarityName = s, rn end
        end
    end
    return info
end

local function scanServer()
    local found, seen = {}, {}
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") then
            local model = v:FindFirstAncestorOfClass("Model")
            if model and not seen[model] then
                seen[model] = true
                local info = inspectModel(model, v)
                if info and (info.income > 0 or info.rarityScore > 0) then
                    table.insert(found, info)
                end
            end
        end
    end
    table.sort(found, function(a, b)
        if a.income ~= b.income then return a.income > b.income end
        return a.rarityScore > b.rarityScore
    end)
    return found
end

local function minRarityScore()
    local name = RARITIES[F.MinRarityIdx]
    if name == "Any" then return 0 end
    return RARITY_SCORE[string.lower(name)] or 0
end

local function findTarget(list)
    local needR, needI = minRarityScore(), INCOME_STEPS[F.MinIncomeIdx]
    for _, info in ipairs(list) do
        if info.rarityScore >= needR and info.income >= needI then
            return info
        end
    end
    return nil
end

-- ---------- highlight ----------
local currentHL, currentTag = nil, nil
local function clearMark()
    if currentHL then pcall(function() currentHL:Destroy() end) currentHL = nil end
    if currentTag then pcall(function() currentTag:Destroy() end) currentTag = nil end
end
local function markTarget(info)
    clearMark()
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 210, 0)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.35
    hl.Parent = info.model
    currentHL = hl
    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.new(0, 220, 0, 44)
    gui.StudsOffset = Vector3.new(0, 4.5, 0)
    gui.AlwaysOnTop = true
    gui.Adornee = info.part
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = "⭐ " .. info.name .. "\n" .. info.rarityName .. " - $" .. formatMoney(info.income) .. "/s"
    l.TextColor3 = Color3.fromRGB(255, 220, 60)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 14
    l.TextStrokeTransparency = 0.3
    l.Parent = gui
    gui.Parent = info.model
    currentTag = gui
end

-- ---------- steal ----------
local function trySteal(info)
    for _, d in ipairs(info.model:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local t = string.lower((d.ActionText or "") .. " " .. (d.ObjectText or ""))
            if string.find(t, "steal") then
                pcall(function()
                    if fireproximityprompt then fireproximityprompt(d) end
                end)
                return true
            end
        end
    end
    if info.prompt then
        pcall(function() if fireproximityprompt then fireproximityprompt(info.prompt) end end)
        return true
    end
    return false
end

-- ---------- server hop ----------
local function loadVisited()
    local ok, data = pcall(function()
        if readfile and isfile and isfile(VISITED_FILE) then
            return HttpService:JSONDecode(readfile(VISITED_FILE))
        end
        return {}
    end)
    if ok and type(data) == "table" then return data end
    return {}
end
local function saveVisited(list)
    pcall(function() if writefile then writefile(VISITED_FILE, HttpService:JSONEncode(list)) end end)
end

local function queueReload()
    local code = 'loadstring(game:HttpGet("' .. FINDER_RAW .. '"))()'
    pcall(function()
        local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if q then q(code) end
    end)
end

local hopping = false
local function serverHop(statusFn)
    if hopping then return end
    hopping = true
    local visited = loadVisited()
    table.insert(visited, game.JobId)
    if #visited > 60 then visited = {game.JobId} end
    saveVisited(visited)
    local isVisited = {}
    for _, id in ipairs(visited) do isVisited[id] = true end

    local candidates = {}
    local cursor = nil
    for page = 1, 3 do
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor then url = url .. "&cursor=" .. cursor end
        local ok, raw = pcall(function() return game:HttpGet(url) end)
        if not ok then break end
        local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok2 or not data or not data.data then break end
        for _, s in ipairs(data.data) do
            if s.id and s.id ~= game.JobId and not isVisited[s.id] and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
                table.insert(candidates, s)
            end
        end
        cursor = data.nextPageCursor
        if not cursor then break end
    end

    if #candidates == 0 then
        saveVisited({game.JobId})
        statusFn("No new server found, retrying in 10s...")
        hopping = false
        return
    end
    -- busier servers have more bases = more steal targets
    table.sort(candidates, function(a, b) return a.playing > b.playing end)
    local pick = candidates[math.random(1, math.min(5, #candidates))]
    statusFn("Hopping to a new server (" .. pick.playing .. " players)...")
    queueReload()
    saveSettings()
    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
    end)
    if not ok then hopping = false end
end


-- ---------- GUI ----------
local guiParent = nil
pcall(function() guiParent = gethui and gethui() end)
if not guiParent then guiParent = game:GetService("CoreGui") end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SABFinderGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = guiParent

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 290, 0, 360)
Main.Position = UDim2.new(0.5, -145, 0.4, -180)
Main.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -70, 0, 36)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🔎 Auto Finder - Brainrot"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
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

local Body = Instance.new("Frame")
Body.Size = UDim2.new(1, -16, 1, -48)
Body.Position = UDim2.new(0, 8, 0, 42)
Body.BackgroundTransparency = 1
Body.Parent = Main
local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 6)
Layout.Parent = Body

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, 0, 0, 40)
Status.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
Status.Text = "Status: idle"
Status.TextColor3 = Color3.fromRGB(160, 220, 255)
Status.Font = Enum.Font.Gotham
Status.TextSize = 12
Status.TextWrapped = true
Status.Parent = Body
Instance.new("UICorner", Status).CornerRadius = UDim.new(0, 6)

local function setStatus(t)
    Status.Text = "Status: " .. tostring(t)
end

local toggleButtons = {}
local function addToggle(text, getFn, setFn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32)
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = Body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local function refresh()
        local on = getFn()
        b.Text = "  " .. text .. (on and " : ON" or " : OFF")
        b.BackgroundColor3 = on and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(35, 35, 45)
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
    b.MouseButton1Click:Connect(function()
        setFn(not getFn())
        refresh()
        saveSettings()
    end)
    refresh()
    toggleButtons[text] = refresh
    return b
end

local function addCycle(text, getLabelFn, cycleFn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(60, 55, 30)
    b.TextColor3 = Color3.fromRGB(255, 235, 170)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = Body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local function refresh() b.Text = text .. " : " .. getLabelFn() end
    b.MouseButton1Click:Connect(function()
        cycleFn()
        refresh()
        saveSettings()
    end)
    refresh()
    return b
end

local function addButton(text, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32)
    b.BackgroundColor3 = Color3.fromRGB(50, 80, 140)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Text = text
    b.Parent = Body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function() pcall(cb) end)
    return b
end

addToggle("Auto Finder", function() return F.Enabled end, function(v)
    F.Enabled = v
    if v then notify("Finder ON - target: " .. RARITIES[F.MinRarityIdx] .. "+") end
end)
addCycle("Min Rarity", function() return RARITIES[F.MinRarityIdx] end, function()
    F.MinRarityIdx = F.MinRarityIdx % #RARITIES + 1
end)
addCycle("Min Income $/s", function()
    local v = INCOME_STEPS[F.MinIncomeIdx]
    if v == 0 then return "Any" end
    return "$" .. formatMoney(v) .. "/s"
end, function()
    F.MinIncomeIdx = F.MinIncomeIdx % #INCOME_STEPS + 1
end)
addToggle("Auto Teleport to Target", function() return F.AutoTeleport end, function(v) F.AutoTeleport = v end)
addToggle("Auto Steal on Arrive", function() return F.AutoSteal end, function(v) F.AutoSteal = v end)
addToggle("Auto Server Hop", function() return F.AutoHop end, function(v) F.AutoHop = v end)

addButton("Find Best Now (one scan)", function()
    setStatus("Scanning...")
    local list = scanServer()
    if #list == 0 then
        setStatus("Nothing readable in this server yet - wait a few seconds")
        return
    end
    local best = list[1]
    markTarget(best)
    setStatus("Best here: " .. best.name .. " (" .. best.rarityName .. ", $" .. formatMoney(best.income) .. "/s) - " .. #list .. " brainrots scanned")
    if F.AutoTeleport then
        local root = getRoot()
        if root and best.part then root.CFrame = best.part.CFrame + Vector3.new(0, 3, 6) end
    end
end)

addButton("Server Hop Now", function()
    serverHop(setStatus)
end)

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Body.Visible = not minimized
    Main.Size = minimized and UDim2.new(0, 290, 0, 40) or UDim2.new(0, 290, 0, 360)
    MinBtn.Text = minimized and "+" or "-"
end)
CloseBtn.MouseButton1Click:Connect(function()
    F.Enabled = false
    saveSettings()
    _G.SABFinderRunning = false
    clearMark()
    ScreenGui:Destroy()
end)

-- ---------- main finder loop ----------
task.spawn(function()
    task.wait(4) -- let the game finish loading bases/belt
    if F.Enabled then
        setStatus("Resumed after hop - scanning...")
        if toggleButtons["Auto Finder"] then toggleButtons["Auto Finder"]() end
    end
    while _G.SABFinderRunning do
        if F.Enabled then
            setStatus("Scanning this server...")
            local list = scanServer()
            local target = findTarget(list)
            if target then
                markTarget(target)
                setStatus("FOUND: " .. target.name .. " (" .. target.rarityName .. ", $" .. formatMoney(target.income) .. "/s)")
                notify("Found: " .. target.name .. " - $" .. formatMoney(target.income) .. "/s")
                if F.AutoTeleport then
                    local root = getRoot()
                    if root and target.part then
                        root.CFrame = target.part.CFrame + Vector3.new(0, 3, 6)
                        task.wait(0.4)
                        if F.AutoSteal and _G.SABFinderRunning then
                            trySteal(target)
                        end
                    end
                end
                -- stay on this server while the target is here
                task.wait(5)
            else
                if #list > 0 then
                    local best = list[1]
                    setStatus("No target here. Best: " .. best.name .. " ($" .. formatMoney(best.income) .. "/s). " .. (F.AutoHop and ("Hopping in " .. F.HopWaitSeconds .. "s...") or "Auto Hop is OFF"))
                else
                    setStatus("No brainrots readable yet...")
                end
                if F.AutoHop then
                    local waited = 0
                    while _G.SABFinderRunning and F.Enabled and waited < F.HopWaitSeconds do
                        task.wait(3)
                        waited = waited + 3
                        -- re-check quickly, something rare may spawn / be placed
                        local l2 = scanServer()
                        if findTarget(l2) then waited = F.HopWaitSeconds + 1 end
                    end
                    if _G.SABFinderRunning and F.Enabled and not findTarget(scanServer()) then
                        serverHop(setStatus)
                        task.wait(8)
                    end
                else
                    task.wait(5)
                end
            end
        else
            task.wait(1)
        end
    end
    clearMark()
end)

notify("Auto Finder loaded - set rarity, tap Auto Finder ON")
