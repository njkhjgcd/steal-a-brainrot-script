--=====================================================
-- Steal a Brainrot - FINDER BOT (reporter bot)
-- for Delta Executor - run this on a BOT / ALT account
--
-- This is the bot the big hubs run:
--  * It joins a server, scans it (~14 seconds)
--  * Reports every Mythic+ brainrot it sees to the finder
--    backend, with that server's JobId
--  * Hops to the next server and repeats, forever
--  * Everyone using Auto Finder sees the bot's finds in
--    their list, with a Join button
--
-- SETUP (once, on the bot device):
--  1. Log the ALT account into Roblox + Delta on a spare
--     phone / emulator that can stay on.
--  2. Put this script in Delta's Auto Execute, OR just
--     execute it once - it re-executes itself after every
--     server hop via queue_on_teleport.
--  3. Join Steal a Brainrot. The bot does the rest.
-- The bot never buys or steals anything. It only looks,
-- reports and hops.
--=====================================================

if _G.SABBotRunning then
    _G.SABBotRunning = false
    task.wait(0.3)
end
_G.SABBotRunning = true

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local BACKEND = "https://sabfinder.serveousercontent.com"
local BOT_RAW = "https://raw.githubusercontent.com/njkhjgcd/steal-a-brainrot-script/main/BotReporter.lua"
local VISITED_FILE = "SABBot_Visited.json"
local STATS_FILE = "SABBot_Stats.json"

local REPORT_MIN_SCORE = 5 -- Mythic and above
local REPORT_MIN_INCOME = 100000 -- or very high income even if rarity text was missed
local DWELL_SECONDS = 14

local RARITY_SCORE = {["common"]=1, ["rare"]=2, ["epic"]=3, ["legendary"]=4, ["mythic"]=5, ["brainrot god"]=6, ["god"]=6, ["secret"]=7, ["og"]=8}
local SUFFIX = {K = 1e3, M = 1e6, B = 1e9, T = 1e12}

local stats = {servers = 0, reports = 0, lastFind = "-"}
pcall(function()
    if readfile and isfile and isfile(STATS_FILE) then
        local d = HttpService:JSONDecode(readfile(STATS_FILE))
        if type(d) == "table" then stats = d end
    end
end)
local function saveStats()
    pcall(function() if writefile then writefile(STATS_FILE, HttpService:JSONEncode(stats)) end end)
end

-- ---------- small status gui ----------
local guiParent = nil
pcall(function() guiParent = gethui and gethui() end)
if not guiParent then guiParent = game:GetService("CoreGui") end
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SABBotGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = guiParent
local Label = Instance.new("TextLabel")
Label.Size = UDim2.new(0, 300, 0, 54)
Label.Position = UDim2.new(0, 10, 0, 10)
Label.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
Label.BackgroundTransparency = 0.15
Label.TextColor3 = Color3.fromRGB(160, 255, 170)
Label.Font = Enum.Font.Gotham
Label.TextSize = 12
Label.TextXAlignment = Enum.TextXAlignment.Left
Label.Text = "🤖 Finder Bot: starting..."
Label.Parent = ScreenGui
Instance.new("UICorner", Label).CornerRadius = UDim.new(0, 8)
local function setStatus(extra)
    Label.Text = "🤖 Finder Bot: " .. tostring(stats.servers) .. " servers, " .. tostring(stats.reports) .. " reports\nLast find: " .. tostring(stats.lastFind) .. (extra and ("\n" .. extra) or "")
end
setStatus()

-- ---------- scanning (same reader as the finder) ----------
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
        if name ~= "god" and string.find(low, name, 1, true) then return score, name end
    end
    return 0, nil
end

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

local function scanAndReport()
    local reported = 0
    local seen = {}
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") then
            local model = v:FindFirstAncestorOfClass("Model")
            if model and not seen[model] then
                seen[model] = true
                local info = inspectModel(model, v)
                if info and (info.rarityScore >= REPORT_MIN_SCORE or info.income >= REPORT_MIN_INCOME) then
                    if game.JobId and game.JobId ~= "" then
                        local url = BACKEND .. "/report"
                            .. "?placeId=" .. tostring(game.PlaceId)
                            .. "&jobId=" .. HttpService:UrlEncode(game.JobId)
                            .. "&name=" .. HttpService:UrlEncode(info.name)
                            .. "&rarity=" .. HttpService:UrlEncode(info.rarityName or "")
                            .. "&income=" .. tostring(math.floor(info.income))
                            .. "&by=" .. HttpService:UrlEncode("bot-" .. LocalPlayer.Name)
                        pcall(function() game:HttpGet(url) end)
                        reported = reported + 1
                        stats.lastFind = info.name
                    end
                end
            end
        end
    end
    return reported
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
    pcall(function()
        local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if q then q('loadstring(game:HttpGet("' .. BOT_RAW .. '"))()') end
    end)
end

local hopping = false
local function serverHop()
    if hopping then return false end
    hopping = true
    local visited = loadVisited()
    table.insert(visited, game.JobId)
    if #visited > 80 then visited = {game.JobId} end
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
        hopping = false
        return false
    end
    table.sort(candidates, function(a, b) return a.playing > b.playing end)
    local pick = candidates[math.random(1, math.min(5, #candidates))]
    queueReload()
    local ok = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
    end)
    if not ok then hopping = false end
    return ok
end

TeleportService.TeleportInitFailed:Connect(function()
    hopping = false
end)

-- anti-idle: a small virtual click every 4 minutes
LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- ---------- main bot loop ----------
task.spawn(function()
    task.wait(6) -- bases and belt need a few seconds to load in
    while _G.SABBotRunning do
        local r1 = 0
        pcall(function() r1 = scanAndReport() end)
        task.wait(math.max(2, DWELL_SECONDS - 8))
        local r2 = 0
        if _G.SABBotRunning and not hopping then
            pcall(function() r2 = scanAndReport() end)
        end
        stats.servers = stats.servers + 1
        stats.reports = stats.reports + math.max(r1, r2)
        saveStats()
        setStatus("Hopping to next server...")
        local ok = false
        pcall(function() ok = serverHop() end)
        if not ok then
            setStatus("Hop failed, retrying in 10s...")
            task.wait(10)
        else
            task.wait(30) -- teleport should take us away; if not, loop rescans
            hopping = false
        end
    end
end)

print("[FinderBot] running on @" .. LocalPlayer.Name)
