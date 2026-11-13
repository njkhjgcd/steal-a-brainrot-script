--=====================================================
-- Steal a Brainrot - AUTO FINDER v2 (the real finder)
-- for Delta Executor
--
-- How the real finder works (like the one you remember):
--  * Everyone running this script scans THEIR server.
--  * Good brainrots they see are reported to a shared backend
--    with that server's JobId.
--  * Your finder list shows finds from OTHER servers:
--        La Grande Combinasion - Secret - $10M/s - 12s ago [Join]
--  * Tapping Join teleports you into that exact server.
--
-- So the list fills up as more people run the script.
-- Backend: https://sabfinder.serveousercontent.com (listings expire in 3 min)
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

local BACKEND = "https://sabfinder.serveousercontent.com"
local FINDER_RAW = "https://raw.githubusercontent.com/njkhjgcd/steal-a-brainrot-script/main/AutoFinder.lua"

local RARITIES = {"Any", "Rare", "Epic", "Legendary", "Mythic", "Brainrot God", "Secret", "OG"}
local RARITY_SCORE = {["common"]=1, ["rare"]=2, ["epic"]=3, ["legendary"]=4, ["mythic"]=5, ["brainrot god"]=6, ["god"]=6, ["secret"]=7, ["og"]=8}

local F = {
    Reporter = true,       -- report good brainrots from MY server for others
    MinRarityIdx = 5,      -- display filter default: Mythic and above
    ReportMinScore = 5,    -- report Mythic and above
}

local function notify(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {Title = "Auto Finder", Text = tostring(text), Duration = 4})
    end)
    print("[AutoFinder] " .. tostring(text))
end

local function formatMoney(n)
    n = tonumber(n) or 0
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
    local num, suf = string.match(clean, "([%d%.]+)%s*([KMBT])%s*/s")
    if num then return (tonumber(num) or 0) * (SUFFIX[suf] or 1) end
    num = string.match(clean, "([%d%.]+)%s*/s")
    if num then return tonumber(num) or 0 end
    return 0
end

local function rarityFromText(text)
    if not text then return 0, nil end
    local low = string.lower(tostring(text))
    if string.find(low, "brainrot god") then return 6, "Brainrot God" end
    for name, score in pairs(RARITY_SCORE) do
        if name ~= "god" and string.find(low, name, 1, true) then
            return score, name
        end
    end
    return 0, nil
end

-- ---------- scanning MY server (for the reporter) ----------
local function modelRootPart(model)
    return model:FindFirstChild("HumanoidRootPart", true)
        or model:FindFirstChild("RootPart", true)
        or model:FindFirstChildWhichIsA("BasePart", true)
end

local function inspectModel(model, prompt)
    if Players:GetPlayerFromCharacter(model) then return nil end
    if model == (LocalPlayer and LocalPlayer.Character) then return nil end
    if not modelRootPart(model) then return nil end
    local info = {name = model.Name, income = 0, rarityScore = 0, rarityName = "?"}
    if prompt and prompt.ObjectText and prompt.ObjectText ~= "" then info.name = prompt.ObjectText end
    pcall(function()
        for k, v in pairs(model:GetAttributes()) do
            local lk = string.lower(k)
            if type(v) == "number" and (string.find(lk, "generation") or string.find(lk, "income") or string.find(lk, "money") or string.find(lk, "cash") or string.find(lk, "cps")) then
                if v > info.income then info.income = v end
            elseif type(v) == "string" then
                local s, rn = rarityFromText(v)
                if s > info.rarityScore then info.rarityScore, info.rarityName = s, rn end
                local inc = parseIncome(v)
                if inc > info.income then info.income = inc end
            end
        end
    end)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local inc = parseIncome(d.Text)
            if inc > info.income then info.income = inc end
            local s, rn = rarityFromText(d.Text)
            if s > info.rarityScore then info.rarityScore, info.rarityName = s, rn end
        end
    end
    return info
end

local function scanMyServer()
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
    return found
end

-- ---------- backend ----------
local function httpGet(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and res then return res end
    return nil
end

local function reportFind(info)
    if not game.JobId or game.JobId == "" then return end
    local url = BACKEND .. "/report"
        .. "?placeId=" .. tostring(game.PlaceId)
        .. "&jobId=" .. HttpService:UrlEncode(game.JobId)
        .. "&name=" .. HttpService:UrlEncode(info.name)
        .. "&rarity=" .. HttpService:UrlEncode(info.rarityName or "")
        .. "&income=" .. tostring(math.floor(info.income))
        .. "&by=" .. HttpService:UrlEncode(LocalPlayer.Name)
    httpGet(url)
end

local function fetchFinds()
    local raw = httpGet(BACKEND .. "/list?placeId=" .. tostring(game.PlaceId))
    if not raw then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and data and data.finds then return data.finds end
    return nil
end

local function queueReload()
    pcall(function()
        local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if q then q('loadstring(game:HttpGet("' .. FINDER_RAW .. '"))()') end
    end)
end

local function joinFind(find)
    queueReload()
    notify("Joining server with: " .. tostring(find.name))
    pcall(function()
        TeleportService:TeleportToPlaceInstance(tonumber(find.placeId) or game.PlaceId, find.jobId, LocalPlayer)
    end)
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
Main.Size = UDim2.new(0, 320, 0, 430)
Main.Position = UDim2.new(0.5, -160, 0.5, -215)
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
Title.Text = "🔎 Auto Finder - Other Servers"
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

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -16, 0, 26)
Status.Position = UDim2.new(0, 8, 0, 40)
Status.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
Status.Text = "Status: connecting..."
Status.TextColor3 = Color3.fromRGB(160, 220, 255)
Status.Font = Enum.Font.Gotham
Status.TextSize = 12
Status.Parent = Main
Instance.new("UICorner", Status).CornerRadius = UDim.new(0, 6)

local function setStatus(t) Status.Text = "Status: " .. tostring(t) end

local Controls = Instance.new("Frame")
Controls.Size = UDim2.new(1, -16, 0, 70)
Controls.Position = UDim2.new(0, 8, 0, 72)
Controls.BackgroundTransparency = 1
Controls.Parent = Main
local CLayout = Instance.new("UIListLayout")
CLayout.Padding = UDim.new(0, 6)
CLayout.Parent = Controls

local function addToggle(text, getFn, setFn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 30)
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = Controls
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local function refresh()
        local on = getFn()
        b.Text = "  " .. text .. (on and " : ON" or " : OFF")
        b.BackgroundColor3 = on and Color3.fromRGB(30, 120, 60) or Color3.fromRGB(35, 35, 45)
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
    b.MouseButton1Click:Connect(function() setFn(not getFn()) refresh() end)
    refresh()
    return b
end

local function addCycle(text, getLabelFn, cycleFn, parent, layoutParent)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 30)
    b.BackgroundColor3 = Color3.fromRGB(60, 55, 30)
    b.TextColor3 = Color3.fromRGB(255, 235, 170)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local function refresh() b.Text = text .. " : " .. getLabelFn() end
    b.MouseButton1Click:Connect(function() cycleFn() refresh() end)
    refresh()
    return b
end

addToggle("Reporter (share my server's finds)", function() return F.Reporter end, function(v) F.Reporter = v end)
addCycle("Show Rarity", function() return RARITIES[F.MinRarityIdx] .. "+" end, function()
    F.MinRarityIdx = F.MinRarityIdx % #RARITIES + 1
end, Controls)

local ListFrame = Instance.new("ScrollingFrame")
ListFrame.Size = UDim2.new(1, -16, 1, -190)
ListFrame.Position = UDim2.new(0, 8, 0, 150)
ListFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 33)
ListFrame.ScrollBarThickness = 3
ListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ListFrame.Parent = Main
Instance.new("UICorner", ListFrame).CornerRadius = UDim.new(0, 8)
local LLayout = Instance.new("UIListLayout")
LLayout.Padding = UDim.new(0, 5)
LLayout.Parent = ListFrame

local EmptyLabel = Instance.new("TextLabel")
EmptyLabel.Size = UDim2.new(1, -10, 0, 60)
EmptyLabel.Position = UDim2.new(0, 5, 0, 5)
EmptyLabel.BackgroundTransparency = 1
EmptyLabel.Text = "No finds yet.\nThe list fills as players running\nthis script report rare brainrots."
EmptyLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
EmptyLabel.Font = Enum.Font.Gotham
EmptyLabel.TextSize = 12
EmptyLabel.Parent = Main

local function minDisplayScore()
    local name = RARITIES[F.MinRarityIdx]
    if name == "Any" then return 0 end
    return RARITY_SCORE[string.lower(name)] or 0
end

local function renderList(finds)
    for _, c in ipairs(ListFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local need = minDisplayScore()
    local shown = 0
    for _, find in ipairs(finds) do
        local score = 0
        if find.rarity then
            local s = rarityFromText(find.rarity)
            score = s
        end
        -- finds from your own current server are pointless to join
        if score >= need and find.jobId ~= game.JobId then
            shown = shown + 1
            if shown <= 15 then
                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, -6, 0, 48)
                row.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
                row.Parent = ListFrame
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
                local l = Instance.new("TextLabel")
                l.Size = UDim2.new(1, -78, 1, 0)
                l.Position = UDim2.new(0, 8, 0, 0)
                l.BackgroundTransparency = 1
                l.Text = tostring(find.name) .. "\n" .. tostring(find.rarity or "?") .. " - $" .. formatMoney(find.income) .. "/s - " .. tostring(find.age or 0) .. "s ago"
                l.TextColor3 = Color3.fromRGB(255, 255, 255)
                l.Font = Enum.Font.Gotham
                l.TextSize = 12
                l.TextXAlignment = Enum.TextXAlignment.Left
                l.Parent = row
                local join = Instance.new("TextButton")
                join.Size = UDim2.new(0, 62, 0, 34)
                join.Position = UDim2.new(1, -70, 0, 7)
                join.Text = "Join"
                join.BackgroundColor3 = Color3.fromRGB(30, 140, 60)
                join.TextColor3 = Color3.fromRGB(255, 255, 255)
                join.Font = Enum.Font.GothamBold
                join.TextSize = 14
                join.Parent = row
                Instance.new("UICorner", join).CornerRadius = UDim.new(0, 6)
                local captured = find
                join.MouseButton1Click:Connect(function() joinFind(captured) end)
            end
        end
    end
    EmptyLabel.Visible = (shown == 0)
    return shown
end

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Status.Visible = not minimized
    Controls.Visible = not minimized
    ListFrame.Visible = not minimized
    EmptyLabel.Visible = false
    Main.Size = minimized and UDim2.new(0, 320, 0, 40) or UDim2.new(0, 320, 0, 430)
    MinBtn.Text = minimized and "+" or "-"
end)
CloseBtn.MouseButton1Click:Connect(function()
    _G.SABFinderRunning = false
    ScreenGui:Destroy()
end)

-- ---------- loops: fetch list + reporter ----------
task.spawn(function()
    while _G.SABFinderRunning do
        local finds = fetchFinds()
        if finds then
            local shown = renderList(finds)
            setStatus(#finds .. " live find(s), " .. shown .. " shown - updated just now")
        else
            setStatus("backend not answering - retrying (it may be waking up)")
        end
        task.wait(5)
    end
end)

task.spawn(function()
    task.wait(5)
    while _G.SABFinderRunning do
        if F.Reporter then
            pcall(function()
                for _, info in ipairs(scanMyServer()) do
                    if info.rarityScore >= F.ReportMinScore then
                        reportFind(info)
                        task.wait(0.2)
                    end
                end
            end)
        end
        task.wait(12)
    end
end)

notify("Auto Finder v2 loaded - list = finds from other servers")
