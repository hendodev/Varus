--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!
]]
-- More open source scripts at https://xan.bar
-- This WILL NOT WORK ON LOW UNC EXECUTORS LIKE XENO
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

-- Ensure Parvus is loaded
if not Parvus or not Parvus.Utilities or not Parvus.Utilities.UI then
    error("Varus UI system not found. Please load Varus first.")
end

local Tuning = {
    CacheInterval = 0.2,
    TeamScanInterval = 0.5,
    CleanupInterval = 1.0,
    ChamsUpdateInterval = 0.15,
    
    BoxRatio = 0.55,
    CornerLength = 10,
    TracerThickness = 1.5,
    BoxThickness = 1.5,
    
    NameSize = 14,
    DistSize = 12,
    NameOffset = 18,
    DistOffset = 6,
    
    MinBoxSize = 20,
    MaxBoxSize = 400
}

local Palette = {
    Enemy = Color3.fromRGB(255, 75, 85),
    EnemyAlt = Color3.fromRGB(255, 120, 130),
    Friendly = Color3.fromRGB(80, 180, 255),
    Checking = Color3.fromRGB(150, 150, 150),
    Dead = Color3.fromRGB(120, 120, 130),
    
    Tracer = Color3.fromRGB(255, 140, 100),
    ChamsOutline = Color3.fromRGB(255, 255, 255),
    ChamsFill = Color3.fromRGB(255, 75, 85)
}

local State = {
    Unloaded = false,
    LastCache = 0,
    LastTeamScan = 0,
    LastCleanup = 0,
    LastChamsUpdate = 0
}

local Cache = {
    Soldiers = {},
    Positions = {},
    Friendlies = {},
    FriendlyScores = {},
    ConfirmedEnemies = {},
    EnemyConfirmations = {},
    FriendlyIndicators = {},
    LastFriendlyUpdate = {}
}

local ESP = {
    Objects = {},
    Pool = {},
    PoolIndex = 0
}

local Chams = {
    Objects = {}
}

local CharacterFolder = nil
local Connections = {}

local function ClampVector2(v, minX, maxX, minY, maxY)
    return Vector2.new(
        math.clamp(v.X, minX, maxX),
        math.clamp(v.Y, minY, maxY)
    )
end

local function IsValidModel(model)
    if not model or not model.Parent then return false end
    local root = model:FindFirstChild("humanoid_root_part")
    return root ~= nil and root.Parent ~= nil
end

local function GetRoot(model)
    return model:FindFirstChild("humanoid_root_part")
end

local function GetHead(model)
    return model:FindFirstChild("head")
end

local function GetTorso(model)
    return model:FindFirstChild("torso")
end

local function GetLocalRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("humanoid_root_part")
end

local function GetLocalPosition()
    local root = GetLocalRoot()
    if root then return root.Position end
    local cam = Workspace.CurrentCamera
    return cam and cam.CFrame.Position or Vector3.zero
end

local function IsLocalPlayer(model)
    local char = LocalPlayer.Character
    if not char then return false end
    if model == char then return true end
    local myRoot = GetLocalRoot()
    local modelRoot = GetRoot(model)
    if myRoot and modelRoot then
        return (myRoot.Position - modelRoot.Position).Magnitude < 1
    end
    return false
end

local function ScanFriendlyIndicators()
    Cache.FriendlyIndicators = {}
    
    local Window = getgenv().Window
    if not Window or not Window.Flags["ESP/TeamCheck"] then return end
    
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return end
    
    local count = 0
    local maxIndicators = 50
    
    local descendants = playerGui:GetDescendants()
    for i = 1, #descendants do
        if count >= maxIndicators then break end
        
        local gui = descendants[i]
        if not gui:IsA("GuiObject") or not gui.Visible then continue end
        
        local size = gui.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 or size.X >= 20 or size.Y >= 20 then continue end
        
        local isIndicator = false
        
        if gui:IsA("Frame") and gui.BackgroundTransparency < 0.9 then
            local col = gui.BackgroundColor3
            if col.G > 0.5 or col.B > 0.5 then
                isIndicator = true
            end
        elseif gui:IsA("ImageLabel") and gui.ImageTransparency < 0.5 and gui.Image ~= "" then
            isIndicator = true
        end
        
        if isIndicator then
            local pos = gui.AbsolutePosition
            Cache.FriendlyIndicators[count + 1] = Vector2.new(pos.X + size.X/2, pos.Y + size.Y/2)
            count = count + 1
        end
    end
end

local function UpdateFriendlyStatus()
    local Window = getgenv().Window
    if not Window or not Window.Flags["ESP/TeamCheck"] then
        return
    end
    
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local processedModels = {}
    
    for model, data in pairs(Cache.Soldiers) do
        if not IsValidModel(model) then
            Cache.Friendlies[model] = nil
            Cache.FriendlyScores[model] = nil
            Cache.ConfirmedEnemies[model] = nil
            Cache.EnemyConfirmations[model] = nil
            continue
        end
        
        local root = GetRoot(model)
        if not root then continue end
        
        local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
        
        if Cache.ConfirmedEnemies[model] then
            continue
        end
        
        if not onScreen or screenPos.Z <= 0 then
            local enemyConfirms = Cache.EnemyConfirmations[model] or 0
            if enemyConfirms > 0 then
                Cache.EnemyConfirmations[model] = enemyConfirms + 1
                if Cache.EnemyConfirmations[model] >= 2 then
                    Cache.ConfirmedEnemies[model] = true
                    Cache.Friendlies[model] = nil
                    Cache.EnemyConfirmations[model] = 999
                end
            end
            continue
        end
        
        processedModels[model] = true
        
        local screenPos2D = Vector2.new(screenPos.X, screenPos.Y)
        local foundIndicator = false
        
        for i = 1, #Cache.FriendlyIndicators do
            local indicator = Cache.FriendlyIndicators[i]
            local dist = (indicator - screenPos2D).Magnitude
            if dist < 120 then
                foundIndicator = true
                break
            end
        end
        
        local currentScore = Cache.FriendlyScores[model] or 0
        local enemyConfirms = Cache.EnemyConfirmations[model] or 0
        
        if foundIndicator then
            currentScore = math.min(currentScore + 2, 8)
            enemyConfirms = math.max(enemyConfirms - 2, 0)
        else
            currentScore = math.max(currentScore - 1, 0)
            enemyConfirms = enemyConfirms + 2
        end
        
        Cache.FriendlyScores[model] = currentScore
        Cache.EnemyConfirmations[model] = enemyConfirms
        Cache.LastFriendlyUpdate[model] = tick()
        
        if currentScore >= 3 then
            Cache.Friendlies[model] = true
            Cache.ConfirmedEnemies[model] = nil
            Cache.EnemyConfirmations[model] = 0
        elseif enemyConfirms >= 2 then
            Cache.Friendlies[model] = nil
            Cache.ConfirmedEnemies[model] = true
            Cache.EnemyConfirmations[model] = 999
        elseif currentScore <= 0 then
            Cache.Friendlies[model] = nil
        end
    end
    
    for model in pairs(Cache.FriendlyScores) do
        if not processedModels[model] and Cache.Soldiers[model] then
            if not Cache.ConfirmedEnemies[model] then
                local lastUpdate = Cache.LastFriendlyUpdate[model] or 0
                if tick() - lastUpdate > 2 then
                    Cache.FriendlyScores[model] = math.max((Cache.FriendlyScores[model] or 0) - 1, 0)
                    Cache.LastFriendlyUpdate[model] = tick()
                    
                    if Cache.FriendlyScores[model] <= 0 then
                        Cache.Friendlies[model] = nil
                    end
                end
            end
        end
    end
end

local function IsFriendly(model)
    local Window = getgenv().Window
    if not Window or not Window.Flags["ESP/TeamCheck"] then return false end
    if Cache.ConfirmedEnemies[model] then return false end
    return Cache.Friendlies[model] == true
end

local function IsChecking(model)
    local Window = getgenv().Window
    if not Window or not Window.Flags["ESP/TeamCheck"] then return false end
    if Cache.ConfirmedEnemies[model] then return false end
    if Cache.Friendlies[model] == true then return false end
    return true
end

local function GetPlayerStatus(model)
    local Window = getgenv().Window
    if not Window or not Window.Flags["ESP/TeamCheck"] then
        return "neutral", Palette.Enemy
    end
    
    if Cache.ConfirmedEnemies[model] then
        return "enemy", Palette.Enemy
    end
    
    if Cache.Friendlies[model] == true then
        return "friendly", Palette.Friendly
    end
    
    return "checking", Palette.Checking
end

local function CreateESPObject()
    local obj = {
        Box = {},
        Corners = {},
        Name = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
        Tracer = Drawing.new("Line"),
        Fill = Drawing.new("Square")
    }
    
    for i = 1, 4 do
        obj.Box[i] = Drawing.new("Line")
        obj.Box[i].Thickness = Tuning.BoxThickness
        obj.Box[i].Visible = false
    end
    
    for i = 1, 8 do
        obj.Corners[i] = Drawing.new("Line")
        obj.Corners[i].Thickness = Tuning.BoxThickness
        obj.Corners[i].Visible = false
    end
    
    obj.Name.Size = Tuning.NameSize
    obj.Name.Font = Drawing.Fonts.Plex
    obj.Name.Center = true
    obj.Name.Outline = true
    obj.Name.Visible = false
    
    obj.Distance.Size = Tuning.DistSize
    obj.Distance.Font = Drawing.Fonts.Plex
    obj.Distance.Center = true
    obj.Distance.Outline = true
    obj.Distance.Color = Color3.fromRGB(140, 140, 150)
    obj.Distance.Visible = false
    
    obj.Tracer.Thickness = Tuning.TracerThickness
    obj.Tracer.Visible = false
    
    obj.Fill.Filled = true
    obj.Fill.Transparency = 0.15
    obj.Fill.Visible = false
    
    return obj
end

local function HideESP(obj)
    if not obj then return end
    for i = 1, 4 do
        if obj.Box[i] then obj.Box[i].Visible = false end
    end
    for i = 1, 8 do
        if obj.Corners[i] then obj.Corners[i].Visible = false end
    end
    if obj.Name then obj.Name.Visible = false end
    if obj.Distance then obj.Distance.Visible = false end
    if obj.Tracer then obj.Tracer.Visible = false end
    if obj.Fill then obj.Fill.Visible = false end
end

local function DestroyESP(obj)
    if not obj then return end
    pcall(function()
        for i = 1, 4 do
            if obj.Box[i] then obj.Box[i]:Remove() end
        end
        for i = 1, 8 do
            if obj.Corners[i] then obj.Corners[i]:Remove() end
        end
        if obj.Name then obj.Name:Remove() end
        if obj.Distance then obj.Distance:Remove() end
        if obj.Tracer then obj.Tracer:Remove() end
        if obj.Fill then obj.Fill:Remove() end
    end)
end

local function GetPooledESP()
    ESP.PoolIndex = ESP.PoolIndex + 1
    if not ESP.Pool[ESP.PoolIndex] then
        ESP.Pool[ESP.PoolIndex] = CreateESPObject()
    end
    return ESP.Pool[ESP.PoolIndex]
end

local function ResetPool()
    for i = ESP.PoolIndex + 1, #ESP.Pool do
        HideESP(ESP.Pool[i])
    end
    ESP.PoolIndex = 0
end

local function RenderESP(obj, model, cam, screenSize, screenCenter, myPos)
    local Window = getgenv().Window
    if not Window then return end
    
    local root = GetRoot(model)
    if not root then
        HideESP(obj)
        return
    end
    
    local rootPos = root.Position
    local dist = (rootPos - myPos).Magnitude
    
    local maxDist = Window.Flags["ESP/MaxDistance"] or 500
    if dist > maxDist then
        HideESP(obj)
        return
    end
    
    local screenPos, onScreen = cam:WorldToViewportPoint(rootPos)
    
    if not onScreen or screenPos.Z <= 0 then
        HideESP(obj)
        return
    end
    
    local baseHeight = 1200 / math.max(screenPos.Z, 1)
    local boxH = math.clamp(baseHeight, Tuning.MinBoxSize, Tuning.MaxBoxSize)
    local boxW = boxH * Tuning.BoxRatio
    
    local cx, cy = screenPos.X, screenPos.Y
    local halfW, halfH = boxW / 2, boxH / 2
    local top = cy - halfH * 1.1
    local bottom = cy + halfH * 0.9
    local left = cx - halfW
    local right = cx + halfW
    
    local status, color = GetPlayerStatus(model)
    
    if Window.Flags["ESP/Box"] then
        local boxStyleValue = Window.Flags["ESP/BoxStyle"]
        local boxStyle = 1
        if type(boxStyleValue) == "table" and #boxStyleValue > 0 then
            if boxStyleValue[1] == "Corner" then
                boxStyle = 2
            end
        end
        if boxStyle == 1 then
            for i = 1, 8 do obj.Corners[i].Visible = false end
            
            obj.Box[1].From = Vector2.new(left, top)
            obj.Box[1].To = Vector2.new(right, top)
            obj.Box[2].From = Vector2.new(right, top)
            obj.Box[2].To = Vector2.new(right, bottom)
            obj.Box[3].From = Vector2.new(right, bottom)
            obj.Box[3].To = Vector2.new(left, bottom)
            obj.Box[4].From = Vector2.new(left, bottom)
            obj.Box[4].To = Vector2.new(left, top)
            
            for i = 1, 4 do
                obj.Box[i].Color = color
                obj.Box[i].Visible = true
            end
        else
            for i = 1, 4 do obj.Box[i].Visible = false end
            
            local cl = Tuning.CornerLength
            
            obj.Corners[1].From = Vector2.new(left, top)
            obj.Corners[1].To = Vector2.new(left + cl, top)
            obj.Corners[2].From = Vector2.new(left, top)
            obj.Corners[2].To = Vector2.new(left, top + cl)
            
            obj.Corners[3].From = Vector2.new(right, top)
            obj.Corners[3].To = Vector2.new(right - cl, top)
            obj.Corners[4].From = Vector2.new(right, top)
            obj.Corners[4].To = Vector2.new(right, top + cl)
            
            obj.Corners[5].From = Vector2.new(left, bottom)
            obj.Corners[5].To = Vector2.new(left + cl, bottom)
            obj.Corners[6].From = Vector2.new(left, bottom)
            obj.Corners[6].To = Vector2.new(left, bottom - cl)
            
            obj.Corners[7].From = Vector2.new(right, bottom)
            obj.Corners[7].To = Vector2.new(right - cl, bottom)
            obj.Corners[8].From = Vector2.new(right, bottom)
            obj.Corners[8].To = Vector2.new(right, bottom - cl)
            
            for i = 1, 8 do
                obj.Corners[i].Color = color
                obj.Corners[i].Visible = true
            end
        end
    else
        for i = 1, 4 do obj.Box[i].Visible = false end
        for i = 1, 8 do obj.Corners[i].Visible = false end
    end
    
    if Window.Flags["ESP/BoxFill"] then
        obj.Fill.Position = Vector2.new(left, top)
        obj.Fill.Size = Vector2.new(boxW, bottom - top)
        obj.Fill.Color = color
        obj.Fill.Visible = true
    else
        obj.Fill.Visible = false
    end
    
    if Window.Flags["ESP/Name"] and Window.Flags["ESP/TeamCheck"] then
        if status == "friendly" then
            obj.Name.Text = "FRIENDLY"
        elseif status == "checking" then
            obj.Name.Text = "CHECKING"
        else
            obj.Name.Text = "ENEMY"
        end
        obj.Name.Position = Vector2.new(cx, top - Tuning.NameOffset)
        obj.Name.Color = color
        obj.Name.Visible = true
    else
        obj.Name.Visible = false
    end
    
    if Window.Flags["ESP/Distance"] then
        obj.Distance.Text = math.floor(dist) .. "m"
        obj.Distance.Position = Vector2.new(cx, bottom + Tuning.DistOffset)
        obj.Distance.Visible = true
    else
        obj.Distance.Visible = false
    end
    
    if Window.Flags["ESP/Tracer"] then
        local tracerOriginValue = Window.Flags["ESP/TracerOrigin"]
        local tracerOrigin = 1
        if type(tracerOriginValue) == "table" and #tracerOriginValue > 0 then
            if tracerOriginValue[1] == "Center" then
                tracerOrigin = 2
            elseif tracerOriginValue[1] == "Top" then
                tracerOrigin = 3
            end
        end
        local origin
        if tracerOrigin == 1 then
            origin = Vector2.new(screenCenter.X, screenSize.Y)
        elseif tracerOrigin == 2 then
            origin = screenCenter
        else
            origin = Vector2.new(screenCenter.X, 0)
        end
        obj.Tracer.From = origin
        obj.Tracer.To = Vector2.new(cx, bottom)
        obj.Tracer.Color = Palette.Tracer
        obj.Tracer.Visible = true
    else
        obj.Tracer.Visible = false
    end
end

local function CreateChams(model)
    if Chams.Objects[model] then return end
    
    local h = Instance.new("Highlight")
    h.Name = "Highlight"
    h.Adornee = model
    h.FillColor = Palette.ChamsFill
    h.OutlineColor = Palette.ChamsOutline
    h.FillTransparency = 0.7
    local Window = getgenv().Window
    h.OutlineTransparency = (Window and Window.Flags["ESP/ChamsOutline"]) and 0 or 1
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = model
    
    Chams.Objects[model] = h
end

local function UpdateChams(model)
    local h = Chams.Objects[model]
    if not h or not h.Parent then return end
    
    local Window = getgenv().Window
    if not Window then return end
    
    local status, fillColor = GetPlayerStatus(model)
    if not Window.Flags["ESP/TeamCheck"] then
        fillColor = Palette.ChamsFill
    elseif status == "friendly" then
        fillColor = Palette.Friendly
    elseif status == "checking" then
        fillColor = Palette.Checking
    else
        fillColor = Palette.ChamsFill
    end
    
    h.FillColor = fillColor
    h.OutlineTransparency = Window.Flags["ESP/ChamsOutline"] and 0 or 1
end

local function RemoveChams(model)
    local h = Chams.Objects[model]
    if not h then return end
    
    pcall(function() h:Destroy() end)
    Chams.Objects[model] = nil
end

local function ClearAllChams()
    for model in pairs(Chams.Objects) do
        RemoveChams(model)
    end
end

local function CacheSoldiers()
    if not CharacterFolder then return end
    
    local Window = getgenv().Window
    if not Window then return end
    
    local children = CharacterFolder:GetChildren()
    local validModels = {}
    local myPos = GetLocalPosition()
    local maxDist = Window.Flags["ESP/MaxDistance"] or 500
    
    for i = 1, #children do
        local model = children[i]
        if not model:IsA("Model") then continue end
        if not IsValidModel(model) then continue end
        if IsLocalPlayer(model) then continue end
        
        local root = GetRoot(model)
        if root then
            local dist = (root.Position - myPos).Magnitude
            if dist <= maxDist then
                validModels[model] = true
                if not Cache.Soldiers[model] then
                    Cache.Soldiers[model] = { added = tick() }
                end
            end
        end
    end
    
    for model in pairs(Cache.Soldiers) do
        if not validModels[model] then
            Cache.Soldiers[model] = nil
            Cache.Friendlies[model] = nil
            Cache.FriendlyScores[model] = nil
            Cache.ConfirmedEnemies[model] = nil
            Cache.EnemyConfirmations[model] = nil
            Cache.LastFriendlyUpdate[model] = nil
            RemoveChams(model)
        end
    end
end

local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1.5
FOVCircle.NumSides = 64
FOVCircle.Filled = false
FOVCircle.Visible = false
FOVCircle.Color = Color3.fromRGB(255, 75, 85)
FOVCircle.Transparency = 0.7

local function GetClosestTarget(cam, mousePos)
    local Window = getgenv().Window
    if not Window then return nil end
    
    local closestTarget = nil
    local shortestDistance = Window.Flags["AIM/FOV"] or 180
    
    for model in pairs(Cache.Soldiers) do
        if Window.Flags["AIM/TeamCheck"] and IsFriendly(model) then continue end
        if Window.Flags["ESP/TeamCheck"] and IsChecking(model) then continue end
        if not IsValidModel(model) then continue end
        
        local targetPart
        local targetPartValue = Window.Flags["AIM/TargetPart"]
        local targetPartSetting = 1
        if type(targetPartValue) == "table" and #targetPartValue > 0 then
            if targetPartValue[1] == "Torso" then
                targetPartSetting = 2
            elseif targetPartValue[1] == "Root" then
                targetPartSetting = 3
            end
        end
        if targetPartSetting == 1 then
            targetPart = GetHead(model)
        elseif targetPartSetting == 2 then
            targetPart = GetTorso(model)
        else
            targetPart = GetRoot(model)
        end
        
        if not targetPart then continue end
        
        local screenPos, onScreen = cam:WorldToViewportPoint(targetPart.Position)
        if not onScreen or screenPos.Z <= 0 then continue end
        
        local screenDist = (mousePos - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
        if screenDist < shortestDistance then
            shortestDistance = screenDist
            closestTarget = model
        end
    end
    
    return closestTarget
end

local function ProcessAimbot(cam, screenCenter)
    local Window = getgenv().Window
    if not Window then return end
    
    local mousePos = UserInputService:GetMouseLocation()
    local isHoldingRMB = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    
    FOVCircle.Position = mousePos
    FOVCircle.Radius = Window.Flags["AIM/FOV"] or 180
    FOVCircle.Visible = Window.Flags["AIM/Enabled"] and Window.Flags["AIM/ShowFOV"]
    FOVCircle.Color = isHoldingRMB and Color3.fromRGB(85, 220, 120) or Color3.fromRGB(255, 75, 85)
    
    if not Window.Flags["AIM/Enabled"] then return end
    if not isHoldingRMB then return end
    
    local target = GetClosestTarget(cam, mousePos)
    if not target then return end
    
    local targetPart
    local targetPartValue = Window.Flags["AIM/TargetPart"]
    local targetPartSetting = 1
    if type(targetPartValue) == "table" and #targetPartValue > 0 then
        if targetPartValue[1] == "Torso" then
            targetPartSetting = 2
        elseif targetPartValue[1] == "Root" then
            targetPartSetting = 3
        end
    end
    if targetPartSetting == 1 then
        targetPart = target:FindFirstChild("head")
    elseif targetPartSetting == 2 then
        targetPart = target:FindFirstChild("torso")
    else
        targetPart = target:FindFirstChild("humanoid_root_part")
    end
    
    if not targetPart then return end
    
    local screenPos = cam:WorldToViewportPoint(targetPart.Position)
    local delta = Vector2.new(screenPos.X, screenPos.Y) - mousePos
    local smooth = Window.Flags["AIM/Smooth"] or 0.18
    
    mousemoverel(delta.X * smooth, delta.Y * smooth)
end

local function Unload()
    if State.Unloaded then return end
    State.Unloaded = true
    
    for name, conn in pairs(Connections) do
        pcall(function()
            if conn and conn.Disconnect then
                conn:Disconnect()
            end
        end)
    end
    Connections = {}
    
    for i = 1, #ESP.Pool do
        DestroyESP(ESP.Pool[i])
    end
    ESP.Pool = {}
    
    ClearAllChams()
    
    pcall(function()
        if FOVCircle then FOVCircle:Remove() end
    end)
    
    Cache = {
        Soldiers = {},
        Positions = {},
        Friendlies = {},
        FriendlyScores = {},
        ConfirmedEnemies = {},
        EnemyConfirmations = {},
        FriendlyIndicators = {},
        LastFriendlyUpdate = {}
    }
end

local function MainLoop()
    if State.Unloaded then return end
    
    local Window = getgenv().Window
    if not Window then return end
    
    local now = tick()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local screenSize = cam.ViewportSize
    local screenCenter = Vector2.new(screenSize.X / 2, screenSize.Y / 2)
    
    if now - State.LastCache > Tuning.CacheInterval then
        State.LastCache = now
        CacheSoldiers()
    end
    
    if Window.Flags["ESP/TeamCheck"] and now - State.LastTeamScan > Tuning.TeamScanInterval then
        State.LastTeamScan = now
        ScanFriendlyIndicators()
        UpdateFriendlyStatus()
    end
    
    if now - State.LastCleanup > Tuning.CleanupInterval then
        State.LastCleanup = now
        for model in pairs(Cache.Soldiers) do
            if not IsValidModel(model) then
                Cache.Soldiers[model] = nil
                Cache.Friendlies[model] = nil
                Cache.FriendlyScores[model] = nil
                Cache.ConfirmedEnemies[model] = nil
                Cache.EnemyConfirmations[model] = nil
                Cache.LastFriendlyUpdate[model] = nil
                RemoveChams(model)
            end
        end
    end
    
    ResetPool()
    
    if Window.Flags["ESP/Enabled"] then
        local myPos = GetLocalPosition()
        local maxDistSq = (Window.Flags["ESP/MaxDistance"] or 500) * (Window.Flags["ESP/MaxDistance"] or 500)
        
        for model in pairs(Cache.Soldiers) do
            if not IsValidModel(model) then continue end
            if Window.Flags["ESP/TeamCheck"] and IsFriendly(model) then continue end
            
            local root = GetRoot(model)
            if not root then continue end
            
            local rootPos = root.Position
            local distVec = rootPos - myPos
            local distSq = distVec.X * distVec.X + distVec.Y * distVec.Y + distVec.Z * distVec.Z
            if distSq > maxDistSq then continue end
            
            local espObj = GetPooledESP()
            RenderESP(espObj, model, cam, screenSize, screenCenter, myPos)
        end
    end
    
    if Window.Flags["ESP/Chams"] then
        if now - State.LastChamsUpdate > Tuning.ChamsUpdateInterval then
            State.LastChamsUpdate = now
            
            for model in pairs(Cache.Soldiers) do
                if not IsValidModel(model) then continue end
                if Window.Flags["ESP/TeamCheck"] and IsFriendly(model) then
                    RemoveChams(model)
                    continue
                end
                
                if not Chams.Objects[model] then
                    CreateChams(model)
                else
                    UpdateChams(model)
                end
            end
        end
    else
        if next(Chams.Objects) then
            ClearAllChams()
        end
    end
    
    ProcessAimbot(cam, screenCenter)
end

local FPSOptimizer = {
    Enabled = false,
    LastOptimize = 0,
    OptimizeInterval = 3.0
}

local function OptimizeFPS()
    if not FPSOptimizer.Enabled then return end
    
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.ShadowSoftness = 0
        Lighting.Brightness = 1.5
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
        Lighting.Ambient = Color3.fromRGB(128, 128, 128)
    end)
    
    pcall(function()
        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("BlurEffect") or effect:IsA("BloomEffect") or 
               effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") or
               effect:IsA("ColorCorrectionEffect") then
                effect.Enabled = false
            end
        end
    end)
    
    pcall(function()
        settings().Rendering.QualityLevel = 1
    end)
end

local function InitializeFPSOptimizer()
    Connections.FPSOptimizer = RunService.Heartbeat:Connect(function()
        if FPSOptimizer.Enabled then
            local now = tick()
            if now - FPSOptimizer.LastOptimize > FPSOptimizer.OptimizeInterval then
                OptimizeFPS()
                FPSOptimizer.LastOptimize = now
            end
        end
    end)
    
    Connections.WorkspaceDescendantAdded = Workspace.DescendantAdded:Connect(function(descendant)
        if FPSOptimizer.Enabled then
            pcall(function()
                if descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Smoke") then
                    descendant.Enabled = false
                elseif descendant:IsA("Beam") or descendant:IsA("Trail") then
                    descendant.Enabled = false
                elseif descendant:IsA("Explosion") then
                    descendant.BlastRadius = 0
                end
            end)
        end
    end)
end

local function HandleInput(input, gameProcessed)
    if State.Unloaded then return end
    
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Home then
            Unload()
            return
        end
        
        if input.KeyCode == Enum.KeyCode.End then
            FPSOptimizer.Enabled = not FPSOptimizer.Enabled
            if FPSOptimizer.Enabled then
                OptimizeFPS()
            end
            return
        end
    end
end

local function Initialize()
    CharacterFolder = Workspace:WaitForChild("characters", 10)
    
    if not CharacterFolder then
        warn("Could not find characters folder")
        return
    end
    
    -- Create Varus UI Window
    local Window = Parvus.Utilities.UI:Window({
        Name = "DEADLINE",
        Position = UDim2.new(0.5, -248, 0.5, -248)
    })
    
    -- Store Window globally for access
    getgenv().Window = Window
    
    -- ESP Tab
    local ESPTab = Window:Tab({Name = "ESP"}) do
        local ESPSettingsSection = ESPTab:Section({Name = "ESP Settings", Side = "Left"}) do
            ESPSettingsSection:Toggle({Name = "Enable ESP", Flag = "ESP/Enabled", Value = true})
            ESPSettingsSection:Toggle({Name = "Box ESP", Flag = "ESP/Box", Value = true})
            ESPSettingsSection:Dropdown({Name = "Box Style", Flag = "ESP/BoxStyle", List = {
                {Name = "Full", Mode = "Button", Value = true},
                {Name = "Corner", Mode = "Button"}
            }})
            ESPSettingsSection:Toggle({Name = "Box Fill", Flag = "ESP/BoxFill", Value = false})
            ESPSettingsSection:Toggle({Name = "Name", Flag = "ESP/Name", Value = true})
            ESPSettingsSection:Toggle({Name = "Distance", Flag = "ESP/Distance", Value = true})
            ESPSettingsSection:Slider({Name = "Max Distance", Flag = "ESP/MaxDistance", Min = 500, Max = 3000, Value = 500, Step = 50})
            ESPSettingsSection:Toggle({Name = "Tracer", Flag = "ESP/Tracer", Value = false})
            ESPSettingsSection:Dropdown({Name = "Tracer Origin", Flag = "ESP/TracerOrigin", List = {
                {Name = "Bottom", Mode = "Button", Value = true},
                {Name = "Center", Mode = "Button"},
                {Name = "Top", Mode = "Button"}
            }})
            ESPSettingsSection:Toggle({Name = "Team Check", Flag = "ESP/TeamCheck", Value = true})
        end
        
        local ChamsSection = ESPTab:Section({Name = "Chams", Side = "Right"}) do
            ChamsSection:Toggle({Name = "Enable Chams", Flag = "ESP/Chams", Value = false, Callback = function(Bool)
                if not Bool then
                    ClearAllChams()
                end
            end})
            ChamsSection:Toggle({Name = "Chams Outline", Flag = "ESP/ChamsOutline", Value = true})
        end
    end
    
    -- AIM Tab
    local AIMTab = Window:Tab({Name = "AIM"}) do
        local AimbotSection = AIMTab:Section({Name = "Aimbot Settings", Side = "Left"}) do
            AimbotSection:Toggle({Name = "Enable Aimbot", Flag = "AIM/Enabled", Value = false})
            AimbotSection:Toggle({Name = "Show FOV", Flag = "AIM/ShowFOV", Value = true})
            AimbotSection:Slider({Name = "FOV Size", Flag = "AIM/FOV", Min = 50, Max = 400, Value = 180, Step = 10})
            AimbotSection:Slider({Name = "Smoothness", Flag = "AIM/Smooth", Min = 0.05, Max = 0.5, Value = 0.18, Precise = 2})
            AimbotSection:Dropdown({Name = "Target Part", Flag = "AIM/TargetPart", List = {
                {Name = "Head", Mode = "Button", Value = true},
                {Name = "Torso", Mode = "Button"},
                {Name = "Root", Mode = "Button"}
            }})
            AimbotSection:Toggle({Name = "Team Check", Flag = "AIM/TeamCheck", Value = true})
        end
    end
    
    InitializeFPSOptimizer()
    
    Connections.Render = RunService.RenderStepped:Connect(MainLoop)
    Connections.Input = UserInputService.InputBegan:Connect(HandleInput)
    
    Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
        ClearAllChams()
        Cache.Soldiers = {}
        Cache.Friendlies = {}
        Cache.FriendlyScores = {}
        Cache.ConfirmedEnemies = {}
        Cache.EnemyConfirmations = {}
        Cache.LastFriendlyUpdate = {}
    end)
end

Initialize()
