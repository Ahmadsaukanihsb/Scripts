local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Networking = require(Shared.Networking)
local KickConfig = require(Shared.Config.KickConfig)
local KickRemotes = require(Shared.Remotes.KickRemotes)
local WeaponRemotes = require(Shared.Remotes.WeaponRemotes)

local LocalPlayer = Players.LocalPlayer

local Kick = Networking.GetRemote(KickRemotes.Remote)
local Weapon = Networking.GetRemote(WeaponRemotes.Remote)

local KICK_COOLDOWN = KickConfig.KickCooldown or 2.85
local CLICK_INTERVAL = 0.1
local KICK_INTERVAL = KICK_COOLDOWN + 0.15
local AFK_INTERVAL = 60
local VK_F13 = 0x7C
local ToggleKey = Enum.KeyCode.RightControl

local genv = getgenv()
genv.AutoKick = genv.AutoKick or { enabled = false, kicks = 0, clicks = 0, lastHeight = "0" }
local S = genv.AutoKick

local statusText = Drawing.new("Text")
statusText.Visible = true
statusText.Center = false
statusText.Position = Vector2.new(12, 46)
statusText.Size = 16
statusText.Outline = true
statusText.OutlineColor = Color3.new(0, 0, 0)
statusText.Color = Color3.new(0.35, 1, 0.55)
statusText.Font = Drawing.Fonts.Monospace
statusText.Text = "AutoKick [RightControl]: OFF"

local function log(...)
    local parts = {}
    for _, v in { ... } do
        parts[#parts + 1] = tostring(v)
    end
    print("[AutoKick]", table.concat(parts, " "))
end

local function updateStatus()
    local on = S.enabled and "ON" or "OFF"
    statusText.Text = string.format("AutoKick [RightControl]: %s | Kicks: %d | Clicks: %d | Last: %s studs",
        on, S.kicks, S.clicks, S.lastHeight)
end

local function toggle()
    S.enabled = not S.enabled
    log(S.enabled and "ENABLED" or "DISABLED")
    updateStatus()
end

local lastKick = 0
local lastClick = 0
local lastAfk = 0

Kick:OnClient(KickRemotes.KickResult, function(height, cash, isAuto)
    if height ~= nil then
        S.lastHeight = tostring(height)
    end
end)

task.spawn(function()
    while true do
        if S.enabled then
            local now = os.clock()

            if now - lastClick >= CLICK_INTERVAL then
                lastClick = now
                Weapon:FireServer(WeaponRemotes.Train)
                S.clicks += 1
            end

            if now - lastKick >= KICK_INTERVAL then
                lastKick = now
                Kick:FireServer(KickRemotes.KickRequest)
                S.kicks += 1
                updateStatus()
            end

            if now - lastAfk >= AFK_INTERVAL then
                lastAfk = now
                keypress(VK_F13)
                task.wait(0.08)
                keyrelease(VK_F13)
            end
        end
        task.wait(0.05)
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == ToggleKey and not gameProcessed then
        toggle()
    end
end)

updateStatus()
log("loaded. Press RightControl to toggle.")
