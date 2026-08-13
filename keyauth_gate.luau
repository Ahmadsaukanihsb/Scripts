local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local KEYAUTH_NAME = "Kick Ball To Space"
local KEYAUTH_OWNERID = "qhsWxvSstr"
local KEYAUTH_VERSION = "1.0"

local HUB_URL = nil -- distribution: full URL, loadstring'd after auth
local HUB_PATH = "C:\\Users\\Administrator\\Desktop\\Scripts\\kickball_hub.luau" -- local dev: read via readfile
local RAYFIELD_URL = "https://sirius.menu/gen2"

local gate = {}
local sessionid = ""

local function log(...)
    print("[KeyAuthGate]", ...)
end

local function notify(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = 5,
        })
    end)
end

local function apiCall(params)
    local url = "https://keyauth.win/api/1.1/?name=" .. HttpService:UrlEncode(KEYAUTH_NAME)
        .. "&ownerid=" .. HttpService:UrlEncode(KEYAUTH_OWNERID)
    for k, v in params do
        url = url .. "&" .. tostring(k) .. "=" .. HttpService:UrlEncode(tostring(v))
    end
    local ok, res = pcall(function()
        return HttpService:GetAsync(url)
    end)
    if not ok then
        return nil, "request failed: " .. tostring(res)
    end
    local okDec, data = pcall(function()
        return HttpService:JSONDecode(res)
    end)
    if not okDec then
        return nil, "bad response: " .. tostring(res)
    end
    return data, nil
end

function gate.authenticate(key)
    if KEYAUTH_NAME == "" or KEYAUTH_OWNERID == "" then
        return false, "Set KEYAUTH_NAME / KEYAUTH_OWNERID in the script"
    end
    local init, err = apiCall({ type = "init", ver = KEYAUTH_VERSION })
    if not init then
        return false, err
    end
    if not init.success then
        return false, "init: " .. tostring(init.message or "failed")
    end
    sessionid = init.sessionid

    local lic, err2 = apiCall({
        type = "license",
        key = key,
        ver = KEYAUTH_VERSION,
        sessionid = sessionid,
    })
    if not lic then
        return false, err2
    end
    if not lic.success then
        return false, "license: " .. tostring(lic.message or "invalid key")
    end
    log("Authorized:", tostring(lic.info and lic.info.username))
    return true, lic
end

local function runHub()
    if HUB_URL then
        local ok, src = pcall(function()
            return game:HttpGet(HUB_URL)
        end)
        if not ok or type(src) ~= "string" then
            return false, "hub download: " .. tostring(src)
        end
        return pcall(loadstring, src)
    end
    local ok, src = pcall(function()
        return readfile(HUB_PATH)
    end)
    if not ok then
        return false, "readfile(" .. HUB_PATH .. "): " .. tostring(src)
    end
    return pcall(loadstring, src)
end

task.spawn(function()
    local okLib, lib = pcall(function()
        return loadstring(game:HttpGet(RAYFIELD_URL))()
    end)
    if not okLib or type(lib) ~= "table" then
        notify("KeyAuth Gate", "Failed to load UI: " .. tostring(lib))
        return
    end
    local Rayfield = lib

    local window = Rayfield:CreateWindow({
        name = "Kick Ball Hub",
        subtitle = "Authenticate to unlock",
        configuration = { autoSave = false },
    })
    local tab = window:CreateTab({ name = "Auth", icon = 93364949241311 })

    local keyInput = tab:CreateInput({
        name = "License Key",
        placeholder = "Enter your key",
        clearOnFocus = true,
        forgetState = true,
        callback = function() end,
    })

    tab:CreateButton({
        name = "Activate Key",
        callback = function()
            local key = tostring(keyInput.value or ""):gsub("%s+", "")
            if key == "" then
                window:Notify({ title = "KeyAuth", content = "Please enter your key." })
                return
            end
            window:Notify({ title = "KeyAuth", content = "Validating key..." })
            task.spawn(function()
                local ok, result = gate.authenticate(key)
                if not ok then
                    window:Notify({ title = "KeyAuth", content = "Error: " .. tostring(result) })
                    log("Auth failed:", tostring(result))
                    return
                end
                window:Notify({ title = "KeyAuth", content = "Authorized. Loading hub..." })
                task.wait(0.5)
                local runOk, runErr = runHub()
                if not runOk then
                    window:Notify({ title = "KeyAuth", content = "Hub error: " .. tostring(runErr) })
                    log("Hub failed to load:", tostring(runErr))
                    return
                end
                window:Destroy()
            end)
        end,
    })
end)

return gate