-- Loader - exactly like the Kurdhub example
-- Give people ONLY this one line:
--
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/njkhjgcd/steal-a-brainrot-script/main/loader.lua"))()
--

local p = game.PlaceId
local url

if p == 109983668079237 or p == 96342491571673 then
    -- Steal a Brainrot (main place + second place)
    url = "https://raw.githubusercontent.com/njkhjgcd/steal-a-brainrot-script/main/StealABrainrot.lua"
else
    -- Still load the hub, it works as a universal menu elsewhere too
    url = "https://raw.githubusercontent.com/njkhjgcd/steal-a-brainrot-script/main/StealABrainrot.lua"
end

local content = game:HttpGet(url)
local fn = loadstring(content)
if fn then
    fn()
end
