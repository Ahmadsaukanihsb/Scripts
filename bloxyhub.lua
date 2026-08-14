local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Networking = require(Shared.Networking)
local KickConfig = require(Shared.Config.KickConfig)
local KickRemotes = require(Shared.Remotes.KickRemotes)
local WeaponRemotes = require(Shared.Remotes.WeaponRemotes)
local RebirthRemotes = require(Shared.Remotes.RebirthRemotes)
local BallRemotes = require(Shared.Remotes.BallRemotes)
local JerseyRemotes = require(Shared.Remotes.JerseyRemotes)
local PackRemotes = require(Shared.Remotes.PackRemotes)
local PackRegistry = require(Shared.Modules.Game.PackRegistry)

local LocalPlayer = Players.LocalPlayer

local Kick = Networking.GetRemote(KickRemotes.Remote)
local Weapon = Networking.GetRemote(WeaponRemotes.Remote)
local Rebirth = Networking.GetRemote(RebirthRemotes.Remote)
local Ball = Networking.GetRemote(BallRemotes.Remote)
local Jersey = Networking.GetRemote(JerseyRemotes.Remote)
local Pack = Networking.GetRemote(PackRemotes.Remote)

local KICK_INTERVAL = (KickConfig.KickCooldown or 2.85) + 0.15
local CLICK_INTERVAL = 0.1
local REBIRTH_CHECK_INTERVAL = 5
local BUY_INTERVAL = 15
local AFK_INTERVAL = 60
local REBIRTH_BACKOFF = 30
local VK_F13 = 0x7C

local genv = getgenv()
genv.KickBallHub = genv.KickBallHub or {
    autoClick = false,
    autoKick = false,
    autoRebirth = false,
    autoBalls = false,
    autoJerseys = false,
    autoEquip = false,
    autoOpenPacks = false,
    packChoice = "BeginnerPack",
    rebirthTrophyTarget = 100,
    clicks = 0,
    kicks = 0,
    rebirths = 0,
    packsOpened = 0,
    ballsBought = 0,
    jerseysBought = 0,
    lastHeight = "0",
    lastRebirthFail = 0,
    lastBuyFail = 0,
    lastPackFail = 0,
}
local S = genv.KickBallHub

S.autoOpenPacks = S.autoOpenPacks == true
S.packChoice = type(S.packChoice) == "string" and S.packChoice or "BeginnerPack"
S.packsOpened = S.packsOpened or 0
S.lastPackFail = S.lastPackFail or 0
S.rebirthTrophyTarget = tonumber(S.rebirthTrophyTarget) or 100

local function log(...)
    local parts = {}
    for _, v in { ... } do
        parts[#parts + 1] = tostring(v)
    end
    print("[KickBallHub]", table.concat(parts, " "))
end

local haveRebirthController
local okReq, RebirthController = pcall(require, Shared.Controllers.Economy.Rebirth.RebirthController)
haveRebirthController = okReq and type(RebirthController) == "table" and type(RebirthController.CanRebirth) == "function"
if not haveRebirthController then
    log("RebirthController unavailable, will attempt rebirth directly")
end

local function canRebirth()
    if haveRebirthController then
        local okBig, Big = pcall(require, Shared.Modules.Math.Big)
        if okBig and type(Big) == "table" then
            local okNext, nextTrophies = pcall(RebirthController.GetNextTrophies, RebirthController)
            if okNext and type(nextTrophies) == "table" and type(nextTrophies.mantissa) == "number" then
                return Big.Gte(nextTrophies, Big.New(S.rebirthTrophyTarget))
            end
        end
        local ok, res = pcall(RebirthController.CanRebirth, RebirthController)
        if ok then
            return res == true
        end
    end
    return true
end

local function getData()
    local okC, DataController = pcall(require, Shared.Controllers.Data.DataController)
    if not okC or type(DataController) ~= "table" then
        return nil
    end
    local ok, data = pcall(function()
        return DataController:GetData()
    end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

local function equipBest()
    local data = getData()
    if not data then
        return
    end
    local ownedBalls = data.OwnedBalls
    local equippedBall = data.EquippedBall
    if type(ownedBalls) == "table" and type(equippedBall) == "string" then
        local ok, BallRegistry = pcall(require, Shared.Modules.Game.BallRegistry)
        if ok and type(BallRegistry) == "table" and type(BallRegistry.GetAll) == "function" then
            local target
            local okAll, balls = pcall(BallRegistry.GetAll, BallRegistry)
            if okAll and type(balls) == "table" then
                for _, b in balls do
                    if type(b) == "table" and ownedBalls[b.Id] == true then
                        target = b
                    end
                end
            end
            if target and target.Id ~= equippedBall then
                local p = Ball:InvokeServer(BallRemotes.Equip, target.Id)
                p:andThen(function() end)
                p:catch(function() end)
                log("Equipped ball:", target.Id)
            end
        end
    end
    local ownedJerseys = data.OwnedJerseys
    local equippedJersey = data.EquippedJersey
    if type(ownedJerseys) == "table" and type(equippedJersey) == "string" then
        local ok, JerseyRegistry = pcall(require, Shared.Modules.Game.JerseyRegistry)
        if ok and type(JerseyRegistry) == "table" and type(JerseyRegistry.GetAll) == "function" then
            local best
            local bestBoost = -1
            local okAll, jerseys = pcall(JerseyRegistry.GetAll, JerseyRegistry)
            if okAll and type(jerseys) == "table" then
                for _, j in jerseys do
                    if type(j) == "table" and ownedJerseys[j.Id] == true and (type(j.KickBoost) == "number" and j.KickBoost > bestBoost or type(j.KickBoost) ~= "number") then
                        if type(j.KickBoost) == "number" and j.KickBoost > bestBoost then
                            best = j
                            bestBoost = j.KickBoost
                        end
                    end
                end
            end
            if best and best.Id ~= equippedJersey then
                local p = Jersey:InvokeServer(JerseyRemotes.Equip, best.Id)
                p:andThen(function() end)
                p:catch(function() end)
                log("Equipped jersey:", best.Id, "boost:", best.KickBoost)
            end
        end
    end
end

local lastKick = 0
local lastClick = 0
local lastRebirthCheck = 0
local lastBuy = 0
local lastAfk = 0
local lastPack = 0
local rebirthInFlight = false

Kick:OnClient(KickRemotes.KickResult, function(height)
    if height ~= nil then
        S.lastHeight = tostring(height)
    end
end)

Pack:OnClient(PackRemotes.OpenResult, function()
    S.packsOpened += 1
    S.lastPackFail = 0
end)

Pack:OnClient(PackRemotes.OpenFailed, function(packId, reason)
    if reason ~= "kicking" then
        S.lastPackFail = os.clock()
    end
    log("Pack open failed:", tostring(reason or packId))
end)

local function doRebirth()
    if rebirthInFlight then
        return
    end
    rebirthInFlight = true
    local p = Rebirth:InvokeServer(RebirthRemotes.Request)
    p:andThen(function(success, reason)
        rebirthInFlight = false
        if success == true then
            S.rebirths += 1
            S.lastRebirthFail = 0
            log("REBIRTHED! Total:", S.rebirths)
        else
            S.lastRebirthFail = os.clock()
            log("Rebirth failed:", tostring(reason))
        end
    end)
    p:catch(function(err)
        rebirthInFlight = false
        S.lastRebirthFail = os.clock()
        log("Rebirth error:", tostring(err))
    end)
end

local function doBuyAll(remote, remotesTable, key, countVar)
    local p = remote:InvokeServer(remotesTable.BuyAll)
    p:andThen(function(count, p2, reason)
        if type(count) == "number" and count > 0 then
            S[countVar] += count
            log("Bought", count, key)
        elseif reason == "not_enough_cash" or reason == "rebirth_locked" or reason == "world_locked" then
            S.lastBuyFail = os.clock()
        end
    end)
    p:catch(function()
        S.lastBuyFail = os.clock()
    end)
end

local PACK_INTERVAL = 0.2
local PACK_BACKOFF = 30

local function openPack()
    local ok, PackC = pcall(function()
        return require(Shared.Controllers.Economy.Currency.CurrencyController)
    end)
    if not ok or type(PackC) ~= "table" then
        return
    end
    local okGet, cash = pcall(PackC.Get, PackC, "Cash")
    if not okGet then
        return
    end
    local pack = PackRegistry and PackRegistry.Get(S.packChoice)
    if not pack then
        return
    end
    local okBig, Big = pcall(require, Shared.Modules.Math.Big)
    if not okBig or type(Big) ~= "table" then
        return
    end
    local totalCost = Big.New(pack.Cost)
    if Big.Lt(cash, totalCost) then
        return
    end
    Pack:FireServer(PackRemotes.OpenRequest, pack.Id, 1)
end

task.spawn(function()
    while true do
        local now = os.clock()

        if S.autoClick and now - lastClick >= CLICK_INTERVAL then
            lastClick = now
            Weapon:FireServer(WeaponRemotes.Train)
            S.clicks += 1
        end

        if S.autoKick and now - lastKick >= KICK_INTERVAL then
            lastKick = now
            Kick:FireServer(KickRemotes.KickRequest)
            S.kicks += 1
        end

        if S.autoRebirth and now - lastRebirthCheck >= REBIRTH_CHECK_INTERVAL then
            lastRebirthCheck = now
            if now - S.lastRebirthFail >= REBIRTH_BACKOFF then
                if canRebirth() then
                    doRebirth()
                end
            end
        end

        if (S.autoBalls or S.autoJerseys or S.autoEquip) and now - lastBuy >= BUY_INTERVAL then
            if now - S.lastBuyFail >= REBIRTH_BACKOFF then
                lastBuy = now
                if S.autoBalls then
                    doBuyAll(Ball, BallRemotes, "ball(s)", "ballsBought")
                end
                if S.autoJerseys then
                    doBuyAll(Jersey, JerseyRemotes, "jersey(s)", "jerseysBought")
                end
                if S.autoEquip then
                    equipBest()
                end
            end
        end

        if S.autoOpenPacks and now - lastPack >= PACK_INTERVAL then
            if now - S.lastPackFail >= PACK_BACKOFF then
                lastPack = now
                openPack()
            end
        end

        if (S.autoClick or S.autoKick) and now - lastAfk >= AFK_INTERVAL then
            lastAfk = now
            keypress(VK_F13)
            task.wait(0.08)
            keyrelease(VK_F13)
        end

        task.wait(0.05)
    end
end)

local okLib, loadResult = pcall(loadstring, game:HttpGet("https://sirius.menu/gen2"))
if not okLib or type(loadResult) ~= "function" then
    log("Failed to load Rayfield Gen2:", tostring(loadResult))
    return
end
local okCall, Rayfield = pcall(loadResult)
if not okCall or type(Rayfield) ~= "table" then
    log("Failed to init Rayfield Gen2:", tostring(Rayfield))
    return
end

local window = Rayfield:CreateWindow({
    name = "Kick Ball Hub",
    subtitle = "Free Kick by Mook",
    configuration = {
        autoSave = true,
        autoLoad = true,
        fileName = "KickBallHub",
    },
})

local farmTab = window:CreateTab({ name = "Farm", icon = 93364949241311 })

farmTab:CreateToggle({
    name = "Auto Click",
    description = "Accumulate Power automatically",
    value = S.autoClick,
    flag = "AutoClick",
    callback = function(v)
        S.autoClick = v
        log("AutoClick:", v)
    end,
})

farmTab:CreateToggle({
    name = "Auto Kick",
    description = "Kick the ball every cooldown",
    value = S.autoKick,
    flag = "AutoKick",
    callback = function(v)
        S.autoKick = v
        log("AutoKick:", v)
    end,
})

farmTab:CreateToggle({
    name = "Auto Rebirth",
    description = "Rebirth when the next rebirth would grant at least the Trophy target below",
    value = S.autoRebirth,
    flag = "AutoRebirth",
    callback = function(v)
        S.autoRebirth = v
        log("AutoRebirth:", v)
    end,
})

farmTab:CreateSlider({
    name = "Trophy Target",
    description = "Repeat rebirth once the pending trophies reach this amount",
    range = { 25, 10000 },
    increment = 1,
    value = S.rebirthTrophyTarget,
    suffix = " Trophies",
    flag = "RebirthTrophyTarget",
    callback = function(v)
        S.rebirthTrophyTarget = v
        log("TrophyTarget:", v)
    end,
})

farmTab:CreateToggle({
    name = "Auto Buy Balls",
    description = "Buy every ball you can afford",
    value = S.autoBalls,
    flag = "AutoBuyBalls",
    callback = function(v)
        S.autoBalls = v
        log("AutoBuyBalls:", v)
    end,
})

farmTab:CreateToggle({
    name = "Auto Buy Jerseys",
    description = "Buy every jersey you can afford",
    value = S.autoJerseys,
    flag = "AutoBuyJerseys",
    callback = function(v)
        S.autoJerseys = v
        log("AutoBuyJerseys:", v)
    end,
})

farmTab:CreateToggle({
    name = "Auto Equip Best",
    description = "Equip the strongest ball & jersey you own",
    value = S.autoEquip,
    flag = "AutoEquip",
    callback = function(v)
        S.autoEquip = v
        log("AutoEquip:", v)
    end,
})

farmTab:CreateDropdown({
    name = "Packs",
    description = "Which pack to open",
    options = { "BeginnerPack", "AveragePack", "ProPack", "MasterPack" },
    value = S.packChoice,
    flag = "PackChoice",
    callback = function(v)
        S.packChoice = v
        log("PackChoice:", v)
    end,
})

farmTab:CreateToggle({
    name = "Auto Open Packs",
    description = "Keep opening packs while you can afford them",
    value = S.autoOpenPacks,
    flag = "AutoOpenPacks",
    callback = function(v)
        S.autoOpenPacks = v
        log("AutoOpenPacks:", v)
    end,
})

local infoTab = window:CreateTab({ name = "Stats", icon = 5337481163910 })
local statKicks = infoTab:CreateStat({ name = "Kicks", value = S.kicks })
local statClicks = infoTab:CreateStat({ name = "Clicks", value = S.clicks })
local statRebirths = infoTab:CreateStat({ name = "Rebirths", value = S.rebirths })
local statHeights = infoTab:CreateStat({ name = "Last Kick (studs)", prefix = "", value = tonumber(S.lastHeight) or 0 })
local statPacks = infoTab:CreateStat({ name = "Packs Opened", value = S.packsOpened })
local statNextTrophies = infoTab:CreateStat({ name = "Next Trophies", value = 0 })

task.spawn(function()
    while true do
        statKicks:Set(S.kicks)
        statClicks:Set(S.clicks)
        statRebirths:Set(S.rebirths)
        statHeights:Set(tonumber(S.lastHeight) or 0)
        statPacks:Set(S.packsOpened)
        if haveRebirthController then
            local okNext, nextTrophies = pcall(RebirthController.GetNextTrophies, RebirthController)
            if okNext and type(nextTrophies) == "table" and type(nextTrophies.mantissa) == "number" then
                statNextTrophies:Set(nextTrophies.mantissa * 10 ^ (nextTrophies.exponent or 0))
            end
        end
        task.wait(1)
    end
end)

window:Notify({
    title = "Kick Ball Hub",
    content = "Loaded. Enable the toggles to start farming.",
})
log("loaded")
