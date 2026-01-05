local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

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
    LastFriendlyUpdate = {},
    WallCheckResults = {},
    ClosestEnemy = nil
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

local function GetHumanoid(model)
    return model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("Humanoid")
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

local function DetectTeammates()
    local Window = getgenv().Window
    if not Window or Window.Flags["ESP/TeamCheck"] then return end
    
    local Teams = game:GetService("Teams")
    local LocalPlayer = Players.LocalPlayer
    local myTeam = LocalPlayer.Team
    
    if not myTeam then return end
    
    local myTeamPlayers = {}
    for _, player in pairs(Players:GetPlayers()) do
        if player.Team == myTeam and player ~= LocalPlayer then
            myTeamPlayers[player] = true
        end
    end
    
    for model in pairs(Cache.Soldiers) do
        if not IsValidModel(model) then continue end
        
        local root = GetRoot(model)
        if not root then continue end
        
        local modelPos = root.Position
        local isTeammate = false
        
        for player, _ in pairs(myTeamPlayers) do
            if player.Character then
                local charRoot = player.Character:FindFirstChild("HumanoidRootPart") or player.Character:FindFirstChild("humanoid_root_part")
                if charRoot then
                    local dist = (charRoot.Position - modelPos).Magnitude
                    if dist < 2 then
                        isTeammate = true
                        break
                    end
                end
            end
        end
        
        if not isTeammate then
            pcall(function()
                if model:FindFirstChild("Team") then
                    local modelTeam = model.Team
                    if typeof(modelTeam) == "Instance" and modelTeam:IsA("Team") then
                        isTeammate = (modelTeam == myTeam)
                    elseif typeof(modelTeam) == "string" then
                        isTeammate = (modelTeam == myTeam.Name)
                    end
                end
            end)
        end
        
        if isTeammate then
            Cache.Friendlies[model] = true
            Cache.ConfirmedEnemies[model] = nil
            Cache.EnemyConfirmations[model] = 0
            Cache.FriendlyScores[model] = 8
        else
            if Cache.Friendlies[model] then
                Cache.Friendlies[model] = nil
            end
        end
    end
end

local function ClearTeamCache()
    Cache.Friendlies = {}
    Cache.FriendlyScores = {}
    Cache.ConfirmedEnemies = {}
    Cache.EnemyConfirmations = {}
    Cache.LastFriendlyUpdate = {}
    Cache.WallCheckResults = {}
    Cache.ClosestEnemy = nil
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
                if Cache.EnemyConfirmations[model] >= 4 then
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
        elseif enemyConfirms >= 4 then
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
    if not Window then return false end
    
    if not Window.Flags["ESP/TeamCheck"] then
        return Cache.Friendlies[model] == true
    end
    
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

local function CheckWallBetween(from, to)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    
    local direction = (to - from)
    local distance = direction.Magnitude
    local ray = Workspace:Raycast(from, direction)
    
    if not ray then return true end
    
    local hitDistance = (ray.Position - from).Magnitude
    return hitDistance >= distance * 0.95
end

local function GetPlayerStatus(model)
    local Window = getgenv().Window
    if not Window then
        return "neutral", Palette.Enemy
    end
    
    local enemyColor = Palette.Enemy
    local friendlyColor = Palette.Friendly
    local checkingColor = Palette.Checking
    
    if Window.Flags["ESP/EnemyColor"] then
        local colorData = Window.Flags["ESP/EnemyColor"]
        if type(colorData) == "table" and colorData[6] then
            enemyColor = colorData[6]
        elseif typeof(colorData) == "Color3" then
            enemyColor = colorData
        end
    end
    
    if Window.Flags["ESP/FriendlyColor"] then
        local colorData = Window.Flags["ESP/FriendlyColor"]
        if type(colorData) == "table" and colorData[6] then
            friendlyColor = colorData[6]
        elseif typeof(colorData) == "Color3" then
            friendlyColor = colorData
        end
    end
    
    if Window.Flags["ESP/CheckingColor"] then
        local colorData = Window.Flags["ESP/CheckingColor"]
        if type(colorData) == "table" and colorData[6] then
            checkingColor = colorData[6]
        elseif typeof(colorData) == "Color3" then
            checkingColor = colorData
        end
    end
    
    if not Window.Flags["ESP/TeamCheck"] then
        if Window.Flags["ESP/WallCheck"] then
            local root = GetRoot(model)
            if root then
                local localRoot = GetLocalRoot()
                if localRoot then
                    local isInOpen = Cache.WallCheckResults[model]
                    if isInOpen then
                        return "neutral", Color3.fromRGB(0, 255, 0)
                    end
                end
            end
        end
        
        if Window.Flags["ESP/ClosestEnemy"] and Cache.ClosestEnemy == model then
            local root = GetRoot(model)
            if root then
                local localRoot = GetLocalRoot()
                if localRoot and Window.Flags["ESP/WallCheck"] then
                    local isInOpen = Cache.WallCheckResults[model]
                    if isInOpen then
                        return "neutral", Color3.fromRGB(0, 255, 0)
                    end
                end
                return "neutral", Color3.fromRGB(255, 0, 255)
            end
        end
        
        return "neutral", enemyColor
    end
    
    if Cache.ConfirmedEnemies[model] then
        if Window.Flags["ESP/WallCheck"] then
            local root = GetRoot(model)
            if root then
                local localRoot = GetLocalRoot()
                if localRoot then
                    local isInOpen = Cache.WallCheckResults[model]
                    if isInOpen then
                        return "enemy", Color3.fromRGB(0, 255, 0)
                    end
                end
            end
        end
        
        if Window.Flags["ESP/ClosestEnemy"] and Cache.ClosestEnemy == model then
            local root = GetRoot(model)
            if root then
                local localRoot = GetLocalRoot()
                if localRoot and Window.Flags["ESP/WallCheck"] then
                    local isInOpen = Cache.WallCheckResults[model]
                    if isInOpen then
                        return "enemy", Color3.fromRGB(0, 255, 0)
                    end
                end
                return "enemy", Color3.fromRGB(255, 0, 255)
            end
        end
        
        return "enemy", enemyColor
    end
    
    if Cache.Friendlies[model] == true then
        return "friendly", friendlyColor
    end
    
    return "checking", checkingColor
end

local function CreateESPObject()
    local obj = {
        Box = {},
        Corners = {},
        Box3D = {
            TopLeft = Drawing.new("Line"),
            TopRight = Drawing.new("Line"),
            BottomLeft = Drawing.new("Line"),
            BottomRight = Drawing.new("Line"),
            Left = Drawing.new("Line"),
            Right = Drawing.new("Line"),
            Top = Drawing.new("Line"),
            Bottom = Drawing.new("Line")
        },
        Name = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
        Tracer = Drawing.new("Line"),
        Fill = Drawing.new("Square"),
        Skeleton = {
            Head = Drawing.new("Line"),
            UpperSpine = Drawing.new("Line"),
            LeftShoulder = Drawing.new("Line"),
            LeftUpperArm = Drawing.new("Line"),
            LeftLowerArm = Drawing.new("Line"),
            RightShoulder = Drawing.new("Line"),
            RightUpperArm = Drawing.new("Line"),
            RightLowerArm = Drawing.new("Line"),
            LeftHip = Drawing.new("Line"),
            LeftUpperLeg = Drawing.new("Line"),
            LeftLowerLeg = Drawing.new("Line"),
            RightHip = Drawing.new("Line"),
            RightUpperLeg = Drawing.new("Line"),
            RightLowerLeg = Drawing.new("Line")
        }
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
    
    for _, line in pairs(obj.Box3D) do
        line.Thickness = Tuning.BoxThickness
        line.Visible = false
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
    
    for _, line in pairs(obj.Skeleton) do
        line.Thickness = 1.5
        line.Visible = false
    end
    
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
    if obj.Box3D then
        for _, line in pairs(obj.Box3D) do
            if line then line.Visible = false end
        end
    end
    if obj.Name then obj.Name.Visible = false end
    if obj.Distance then obj.Distance.Visible = false end
    if obj.Tracer then obj.Tracer.Visible = false end
    if obj.Fill then obj.Fill.Visible = false end
    if obj.Skeleton then
        for _, line in pairs(obj.Skeleton) do
            if line then line.Visible = false end
        end
    end
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
        if obj.Box3D then
            for _, line in pairs(obj.Box3D) do
                if line then line:Remove() end
            end
        end
        if obj.Name then obj.Name:Remove() end
        if obj.Distance then obj.Distance:Remove() end
        if obj.Tracer then obj.Tracer:Remove() end
        if obj.Fill then obj.Fill:Remove() end
        if obj.Skeleton then
            for _, line in pairs(obj.Skeleton) do
                if line then line:Remove() end
            end
        end
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
    
    local camCFrame = cam.CFrame
    local camPosition = camCFrame.Position
    local camLookVector = camCFrame.LookVector
    
    local relativePos = rootPos - camPosition
    local dotProduct = camLookVector:Dot(relativePos.Unit)
    
    if dotProduct <= 0 then
        HideESP(obj)
        return
    end
    
    local viewportSize = cam.ViewportSize
    local fov = math.rad(cam.FieldOfView)
    local distance = relativePos.Magnitude
    
    local screenX = (viewportSize.X / 2) + (relativePos.X / relativePos.Z) * (viewportSize.X / (2 * math.tan(fov / 2)))
    local screenY = (viewportSize.Y / 2) - (relativePos.Y / relativePos.Z) * (viewportSize.Y / (2 * math.tan(fov / 2)))
    
    if screenX < -100 or screenX > viewportSize.X + 100 or screenY < -100 or screenY > viewportSize.Y + 100 then
        HideESP(obj)
        return
    end
    
    local baseHeight = 1200 / math.max(distance, 1)
    local boxH = math.clamp(baseHeight, Tuning.MinBoxSize, Tuning.MaxBoxSize)
    local boxW = boxH * Tuning.BoxRatio
    
    local cx, cy = screenX, screenY
    
    local status, color = GetPlayerStatus(model)
    
    local head = GetHead(model)
    local torso = GetTorso(model)
    local modelHeight = 5
    local modelWidth = 2.5
    
    if head and root then
        local headToRoot = (head.Position - root.Position).Magnitude
        modelHeight = headToRoot * 2.2
    end
    if torso and root then
        local torsoToRoot = (torso.Position - root.Position).Magnitude
        modelWidth = math.max(torsoToRoot * 1.5, 2.5)
    end
    
    local modelSizeScreen = cam:WorldToViewportPoint(root.Position + Vector3.new(modelWidth, modelHeight, 0))
    local rootScreen = cam:WorldToViewportPoint(root.Position)
    local screenModelHeight = math.abs(modelSizeScreen.Y - rootScreen.Y) * 2
    local screenModelWidth = math.abs(modelSizeScreen.X - rootScreen.X) * 2
    
    local actualBoxH = math.max(screenModelHeight, boxH)
    local actualBoxW = math.max(screenModelWidth, boxW)
    
    local actualHalfW, actualHalfH = actualBoxW / 2, actualBoxH / 2
    local actualTop = cy - actualHalfH * 1.1
    local actualBottom = cy + actualHalfH * 0.9
    local actualLeft = cx - actualHalfW
    local actualRight = cx + actualHalfW
    
    local halfW, halfH = boxW / 2, boxH / 2
    local top = cy - halfH * 1.1
    local bottom = cy + halfH * 0.9
    local left = cx - halfW
    local right = cx + halfW
    
    if Window.Flags["ESP/Box"] then
        local boxStyleValue = Window.Flags["ESP/BoxStyle"]
        local boxStyle = "Full"
        if type(boxStyleValue) == "table" and #boxStyleValue > 0 then
            boxStyle = boxStyleValue[1]
        end
        
        for i = 1, 4 do obj.Box[i].Visible = false end
        for i = 1, 8 do obj.Corners[i].Visible = false end
        if obj.Box3D then
            for _, line in pairs(obj.Box3D) do
                line.Visible = false
            end
        end
        
        if boxStyle == "ThreeD" then
            local rootCF = root.CFrame
            local head = GetHead(model)
            local torso = GetTorso(model)
            
            local leftArm = model:FindFirstChild("left_arm_vis") or model:FindFirstChild("Left Arm") or model:FindFirstChild("left_arm")
            local rightArm = model:FindFirstChild("right_arm_vis") or model:FindFirstChild("Right Arm") or model:FindFirstChild("right_arm")
            local leftLeg = model:FindFirstChild("left_leg_vis") or model:FindFirstChild("Left Leg") or model:FindFirstChild("left_leg")
            local rightLeg = model:FindFirstChild("right_leg_vis") or model:FindFirstChild("Right Leg") or model:FindFirstChild("right_leg")
            
            local modelHeight = 5
            if head and root then
                local headToRoot = (head.Position - root.Position).Magnitude
                modelHeight = headToRoot * 2.2
            end
            
            local modelWidth = 2.5
            if torso and root then
                local torsoToRoot = (torso.Position - root.Position).Magnitude
                modelWidth = math.max(torsoToRoot * 1.5, 2.5)
                
                if leftArm and rightArm then
                    local leftArmDist = (leftArm.Position - root.Position).Magnitude
                    local rightArmDist = (rightArm.Position - root.Position).Magnitude
                    local maxArmDist = math.max(leftArmDist, rightArmDist)
                    modelWidth = math.max(modelWidth, maxArmDist * 1.2)
                end
            end
            
            local modelDepth = 1.5
            if leftLeg and rightLeg then
                local leftLegDist = (leftLeg.Position - root.Position).Magnitude
                local rightLegDist = (rightLeg.Position - root.Position).Magnitude
                local maxLegDist = math.max(leftLegDist, rightLegDist)
                modelDepth = math.max(modelDepth, maxLegDist * 0.8)
            end
            
            local size = Vector3.new(modelWidth, modelHeight, modelDepth)
            
            local function worldToScreen(worldPos)
                local relativePos = worldPos - camPosition
                local dotProduct = camLookVector:Dot(relativePos.Unit)
                if dotProduct <= 0 then return nil end
                local distance = relativePos.Magnitude
                local fov = math.rad(cam.FieldOfView)
                local screenX = (viewportSize.X / 2) + (relativePos.X / relativePos.Z) * (viewportSize.X / (2 * math.tan(fov / 2)))
                local screenY = (viewportSize.Y / 2) - (relativePos.Y / relativePos.Z) * (viewportSize.Y / (2 * math.tan(fov / 2)))
                return Vector2.new(screenX, screenY), distance
            end
            
            local frontTL, frontTLZ = worldToScreen((rootCF * CFrame.new(-size.X/2, size.Y/2, -size.Z/2)).Position)
            local frontTR, frontTRZ = worldToScreen((rootCF * CFrame.new(size.X/2, size.Y/2, -size.Z/2)).Position)
            local frontBL, frontBLZ = worldToScreen((rootCF * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2)).Position)
            local frontBR, frontBRZ = worldToScreen((rootCF * CFrame.new(size.X/2, -size.Y/2, -size.Z/2)).Position)
            
            local backTL, backTLZ = worldToScreen((rootCF * CFrame.new(-size.X/2, size.Y/2, size.Z/2)).Position)
            local backTR, backTRZ = worldToScreen((rootCF * CFrame.new(size.X/2, size.Y/2, size.Z/2)).Position)
            local backBL, backBLZ = worldToScreen((rootCF * CFrame.new(-size.X/2, -size.Y/2, size.Z/2)).Position)
            local backBR, backBRZ = worldToScreen((rootCF * CFrame.new(size.X/2, -size.Y/2, size.Z/2)).Position)
            
            if not (frontTL and frontTR and frontBL and frontBR and backTL and backTR and backBL and backBR) then
                return
            end
            
            local front = {
                TL = frontTL,
                TR = frontTR,
                BL = frontBL,
                BR = frontBR
            }
            
            local back = {
                TL = backTL,
                TR = backTR,
                BL = backBL,
                BR = backBR
            }
            
            obj.Box3D.TopLeft.From = front.TL
            obj.Box3D.TopLeft.To = front.TR
            obj.Box3D.TopLeft.Color = color
            obj.Box3D.TopLeft.Visible = true
            
            obj.Box3D.TopRight.From = front.TR
            obj.Box3D.TopRight.To = front.BR
            obj.Box3D.TopRight.Color = color
            obj.Box3D.TopRight.Visible = true
            
            obj.Box3D.BottomLeft.From = front.BL
            obj.Box3D.BottomLeft.To = front.BR
            obj.Box3D.BottomLeft.Color = color
            obj.Box3D.BottomLeft.Visible = true
            
            obj.Box3D.BottomRight.From = front.TL
            obj.Box3D.BottomRight.To = front.BL
            obj.Box3D.BottomRight.Color = color
            obj.Box3D.BottomRight.Visible = true
            
            obj.Box3D.Left.From = back.TL
            obj.Box3D.Left.To = back.TR
            obj.Box3D.Left.Color = color
            obj.Box3D.Left.Visible = true
            
            obj.Box3D.Right.From = back.TR
            obj.Box3D.Right.To = back.BR
            obj.Box3D.Right.Color = color
            obj.Box3D.Right.Visible = true
            
            obj.Box3D.Top.From = back.BL
            obj.Box3D.Top.To = back.BR
            obj.Box3D.Top.Color = color
            obj.Box3D.Top.Visible = true
            
            obj.Box3D.Bottom.From = back.TL
            obj.Box3D.Bottom.To = back.BL
            obj.Box3D.Bottom.Color = color
            obj.Box3D.Bottom.Visible = true
            
            local connectors = {
                {From = front.TL, To = back.TL},
                {From = front.TR, To = back.TR},
                {From = front.BL, To = back.BL},
                {From = front.BR, To = back.BR}
            }
            
            for i = 1, 4 do
                if connectors[i] then
                    obj.Box[i].From = connectors[i].From
                    obj.Box[i].To = connectors[i].To
                    obj.Box[i].Color = color
                    obj.Box[i].Visible = true
                end
            end
            
        elseif boxStyle == "Corner" then
            local boxPosition = Vector2.new(actualLeft, actualTop)
            local boxSize = Vector2.new(actualBoxW, actualBoxH)
            local cornerSize = actualBoxW * 0.2
            
            obj.Corners[1].From = boxPosition
            obj.Corners[1].To = boxPosition + Vector2.new(cornerSize, 0)
            obj.Corners[1].Color = color
            obj.Corners[1].Visible = true
            
            obj.Corners[2].From = boxPosition
            obj.Corners[2].To = boxPosition + Vector2.new(0, cornerSize)
            obj.Corners[2].Color = color
            obj.Corners[2].Visible = true
            
            obj.Corners[3].From = boxPosition + Vector2.new(boxSize.X, 0)
            obj.Corners[3].To = boxPosition + Vector2.new(boxSize.X - cornerSize, 0)
            obj.Corners[3].Color = color
            obj.Corners[3].Visible = true
            
            obj.Corners[4].From = boxPosition + Vector2.new(boxSize.X, 0)
            obj.Corners[4].To = boxPosition + Vector2.new(boxSize.X, cornerSize)
            obj.Corners[4].Color = color
            obj.Corners[4].Visible = true
            
            obj.Corners[5].From = boxPosition + Vector2.new(0, boxSize.Y)
            obj.Corners[5].To = boxPosition + Vector2.new(cornerSize, boxSize.Y)
            obj.Corners[5].Color = color
            obj.Corners[5].Visible = true
            
            obj.Corners[6].From = boxPosition + Vector2.new(0, boxSize.Y)
            obj.Corners[6].To = boxPosition + Vector2.new(0, boxSize.Y - cornerSize)
            obj.Corners[6].Color = color
            obj.Corners[6].Visible = true
            
            obj.Corners[7].From = boxPosition + Vector2.new(boxSize.X, boxSize.Y)
            obj.Corners[7].To = boxPosition + Vector2.new(boxSize.X - cornerSize, boxSize.Y)
            obj.Corners[7].Color = color
            obj.Corners[7].Visible = true
            
            obj.Corners[8].From = boxPosition + Vector2.new(boxSize.X, boxSize.Y)
            obj.Corners[8].To = boxPosition + Vector2.new(boxSize.X, boxSize.Y - cornerSize)
            obj.Corners[8].Color = color
            obj.Corners[8].Visible = true
            
        else
            obj.Box[1].From = Vector2.new(actualLeft, actualTop)
            obj.Box[1].To = Vector2.new(actualRight, actualTop)
            obj.Box[2].From = Vector2.new(actualRight, actualTop)
            obj.Box[2].To = Vector2.new(actualRight, actualBottom)
            obj.Box[3].From = Vector2.new(actualRight, actualBottom)
            obj.Box[3].To = Vector2.new(actualLeft, actualBottom)
            obj.Box[4].From = Vector2.new(actualLeft, actualBottom)
            obj.Box[4].To = Vector2.new(actualLeft, actualTop)
            
            for i = 1, 4 do
                obj.Box[i].Color = color
                obj.Box[i].Visible = true
            end
        end
    else
        for i = 1, 4 do obj.Box[i].Visible = false end
        for i = 1, 8 do obj.Corners[i].Visible = false end
        if obj.Box3D then
            for _, line in pairs(obj.Box3D) do
                line.Visible = false
            end
        end
    end
    
    if Window.Flags["ESP/BoxFill"] then
        obj.Fill.Position = Vector2.new(actualLeft, actualTop)
        obj.Fill.Size = Vector2.new(actualBoxW, actualBottom - actualTop)
        
        local fillColor = color
        if Window.Flags["ESP/BoxFillColor"] then
            local colorData = Window.Flags["ESP/BoxFillColor"]
            if type(colorData) == "table" and colorData[6] then
                fillColor = colorData[6]
            elseif typeof(colorData) == "Color3" then
                fillColor = colorData
            end
        end
        
        obj.Fill.Color = fillColor
        obj.Fill.Visible = true
    else
        obj.Fill.Visible = false
    end
    
    if Window.Flags["ESP/Name"] then
        if Window.Flags["ESP/TeamCheck"] then
            if status == "friendly" then
                obj.Name.Text = "FRIENDLY"
            elseif status == "checking" then
                obj.Name.Text = "CHECKING"
            else
                obj.Name.Text = "ENEMY"
            end
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
            origin = Vector2.new(viewportSize.X / 2, viewportSize.Y)
        elseif tracerOrigin == 2 then
            origin = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
        else
            origin = Vector2.new(viewportSize.X / 2, 0)
        end
        obj.Tracer.From = origin
        obj.Tracer.To = Vector2.new(cx, bottom)
        local tracerColor = Palette.Tracer
        if Window.Flags["ESP/TracerColor"] then
            local colorData = Window.Flags["ESP/TracerColor"]
            if type(colorData) == "table" and colorData[6] then
                tracerColor = colorData[6]
            elseif typeof(colorData) == "Color3" then
                tracerColor = colorData
            end
        end
        obj.Tracer.Color = tracerColor
        obj.Tracer.Visible = true
    else
        obj.Tracer.Visible = false
    end
    
    if Window.Flags["ESP/Skeleton"] then
        local function getBonePositions(model)
            if not model then return nil end
            
            local skeletonParts = {
                head = GetHead(model) or model:FindFirstChild("head"),
                torso = GetTorso(model) or model:FindFirstChild("torso"),
                right_arm_vis = model:FindFirstChild("right_arm_vis") or model:FindFirstChild("Right Arm") or model:FindFirstChild("right_arm"),
                left_arm_vis = model:FindFirstChild("left_arm_vis") or model:FindFirstChild("Left Arm") or model:FindFirstChild("left_arm"),
                right_leg_vis = model:FindFirstChild("right_leg_vis") or model:FindFirstChild("Right Leg") or model:FindFirstChild("right_leg"),
                left_leg_vis = model:FindFirstChild("left_leg_vis") or model:FindFirstChild("Left Leg") or model:FindFirstChild("left_leg")
            }
            
            if not (skeletonParts.head and skeletonParts.torso) then return nil end
            
            return skeletonParts
        end
        
        local skeletonParts = getBonePositions(model)
        if skeletonParts then
            for _, line in pairs(obj.Skeleton) do
                line.Visible = false
            end
            
            local function worldToScreenBone(worldPos)
                local relativePos = worldPos - camPosition
                local dotProduct = camLookVector:Dot(relativePos.Unit)
                if dotProduct <= 0 then return nil, false end
                local distance = relativePos.Magnitude
                local fov = math.rad(cam.FieldOfView)
                local screenX = (viewportSize.X / 2) + (relativePos.X / relativePos.Z) * (viewportSize.X / (2 * math.tan(fov / 2)))
                local screenY = (viewportSize.Y / 2) - (relativePos.Y / relativePos.Z) * (viewportSize.Y / (2 * math.tan(fov / 2)))
                if screenX < -100 or screenX > viewportSize.X + 100 or screenY < -100 or screenY > viewportSize.Y + 100 then
                    return nil, false
                end
                return Vector2.new(screenX, screenY), true
            end
            
            local function drawBoneStable(from, to, line)
                if not from or not to then 
                    line.Visible = false
                    return 
                end
                
                local fromScreen, fromVisible = worldToScreenBone(from.Position)
                local toScreen, toVisible = worldToScreenBone(to.Position)
                
                if not (fromVisible and toVisible) then
                    line.Visible = false
                    return
                end
                
                line.From = fromScreen
                line.To = toScreen
                
                local skeletonColor = color
                if Window.Flags["ESP/SkeletonColor"] then
                    local colorData = Window.Flags["ESP/SkeletonColor"]
                    if type(colorData) == "table" and colorData[6] then
                        skeletonColor = colorData[6]
                    elseif typeof(colorData) == "Color3" then
                        skeletonColor = colorData
                    end
                end
                
                line.Color = skeletonColor
                line.Thickness = Window.Flags["ESP/SkeletonThickness"] or 1.5
                line.Visible = true
            end
            
            drawBoneStable(skeletonParts.head, skeletonParts.torso, obj.Skeleton.Head)
            
            if skeletonParts.right_arm_vis then
                drawBoneStable(skeletonParts.torso, skeletonParts.right_arm_vis, obj.Skeleton.RightShoulder)
            end
            
            if skeletonParts.left_arm_vis then
                drawBoneStable(skeletonParts.torso, skeletonParts.left_arm_vis, obj.Skeleton.LeftShoulder)
            end
            
            if skeletonParts.right_leg_vis then
                drawBoneStable(skeletonParts.torso, skeletonParts.right_leg_vis, obj.Skeleton.RightHip)
            end
            
            if skeletonParts.left_leg_vis then
                drawBoneStable(skeletonParts.torso, skeletonParts.left_leg_vis, obj.Skeleton.LeftHip)
            end
        else
            for _, line in pairs(obj.Skeleton) do
                line.Visible = false
            end
        end
    else
        for _, line in pairs(obj.Skeleton) do
            line.Visible = false
        end
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

local PredictionDot = Drawing.new("Circle")
PredictionDot.Thickness = 1
PredictionDot.NumSides = 32
PredictionDot.Filled = true
PredictionDot.Visible = false
PredictionDot.Color = Color3.fromRGB(255, 255, 255)
PredictionDot.Transparency = 0.3

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

local function CalculatePrediction(targetPart, cam, weaponType)
    if not targetPart or not targetPart.Parent then return targetPart.Position end
    
    local Window = getgenv().Window
    if not Window or not Window.Flags["AIM/Prediction"] then
        return targetPart.Position
    end
    
    local weaponTypeValue = Window.Flags["AIM/PredictionType"]
    local weaponTypeStr = "Rifle"
    if type(weaponTypeValue) == "table" and #weaponTypeValue > 0 then
        weaponTypeStr = weaponTypeValue[1]
    end
    
    local bulletSpeed = 1000
    if weaponTypeStr == "Sniper" then
        bulletSpeed = 2000
    elseif weaponTypeStr == "Pistol" then
        bulletSpeed = 800
    elseif weaponTypeStr == "Rifle" then
        bulletSpeed = 1000
    end
    
    local root = GetRoot(targetPart.Parent)
    if not root then return targetPart.Position end
    
    local targetVelocity = root.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    
    local myPos = GetLocalPosition()
    local targetPos = targetPart.Position
    local distance = (targetPos - myPos).Magnitude
    local timeToTarget = distance / bulletSpeed
    
    local predictedPosition = targetPos + (targetVelocity * timeToTarget)
    
    return predictedPosition
end

local function ProcessAimbot(cam, screenCenter)
    local Window = getgenv().Window
    if not Window then 
        PredictionDot.Visible = false
        return 
    end
    
    local mousePos = UserInputService:GetMouseLocation()
    local isHoldingRMB = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    
    local cameraFOV = Window.Flags["AIM/CameraFOV"] or 70
    if cam.FieldOfView ~= cameraFOV then
        cam.FieldOfView = cameraFOV
    end
    
    FOVCircle.Position = mousePos
    FOVCircle.Radius = Window.Flags["AIM/FOV"] or 180
    FOVCircle.Visible = Window.Flags["AIM/Enabled"] and Window.Flags["AIM/ShowFOV"]
    
    local fovColor = Color3.fromRGB(255, 75, 85)
    if Window.Flags["AIM/FOVColor"] then
        local colorData = Window.Flags["AIM/FOVColor"]
        if type(colorData) == "table" and colorData[6] then
            fovColor = colorData[6]
        elseif typeof(colorData) == "Color3" then
            fovColor = colorData
        end
    end
    
    FOVCircle.Color = isHoldingRMB and Color3.fromRGB(85, 220, 120) or fovColor
    
    if not Window.Flags["AIM/Enabled"] then 
        PredictionDot.Visible = false
        return 
    end
    if not isHoldingRMB then 
        PredictionDot.Visible = false
        return 
    end
    
    local target = GetClosestTarget(cam, mousePos)
    if not target then 
        PredictionDot.Visible = false
        return 
    end
    
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
    
    if not targetPart then 
        PredictionDot.Visible = false
        return 
    end
    
    local targetPosition = CalculatePrediction(targetPart, cam, Window.Flags["AIM/PredictionType"])
    local screenPos = cam:WorldToViewportPoint(targetPosition)
    
    if Window.Flags["AIM/Prediction"] and Window.Flags["AIM/PredictionDot"] then
        if screenPos.Z > 0 then
            local dotSize = Window.Flags["AIM/PredictionDotSize"] or 5
            local dotColor = Color3.fromRGB(255, 255, 255)
            if Window.Flags["AIM/PredictionDotColor"] then
                local colorData = Window.Flags["AIM/PredictionDotColor"]
                if type(colorData) == "table" and colorData[6] then
                    dotColor = colorData[6]
                elseif typeof(colorData) == "Color3" then
                    dotColor = colorData
                end
            end
            
            PredictionDot.Position = Vector2.new(screenPos.X, screenPos.Y)
            PredictionDot.Radius = dotSize
            PredictionDot.Color = dotColor
            PredictionDot.Visible = true
        else
            PredictionDot.Visible = false
        end
    else
        PredictionDot.Visible = false
    end
    
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
        if PredictionDot then PredictionDot:Remove() end
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
    
    if now - State.LastTeamScan > Tuning.TeamScanInterval then
        State.LastTeamScan = now
        if Window.Flags["ESP/TeamCheck"] then
            ScanFriendlyIndicators()
            UpdateFriendlyStatus()
        else
            DetectTeammates()
        end
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
                Cache.WallCheckResults[model] = nil
                RemoveChams(model)
            end
        end
    end
    
    local localRoot = GetLocalRoot()
    if localRoot and Window.Flags["ESP/WallCheck"] then
        local myPos = localRoot.Position
        for model in pairs(Cache.Soldiers) do
            if not IsValidModel(model) then continue end
            local root = GetRoot(model)
            if root then
                Cache.WallCheckResults[model] = CheckWallBetween(myPos, root.Position)
            end
        end
    end
    
    Cache.ClosestEnemy = nil
    if Window.Flags["ESP/ClosestEnemy"] and localRoot then
        local myPos = localRoot.Position
        local closestDist = math.huge
        for model in pairs(Cache.Soldiers) do
            if not IsValidModel(model) then continue end
            if Window.Flags["ESP/TeamCheck"] and IsFriendly(model) then continue end
            if Window.Flags["ESP/TeamCheck"] and IsChecking(model) then continue end
            local root = GetRoot(model)
            if root then
                local dist = (root.Position - myPos).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    Cache.ClosestEnemy = model
                end
            end
        end
    end
    
    ResetPool()
    
    if Window.Flags["ESP/Enabled"] then
        local myPos = GetLocalPosition()
        local maxDistSq = (Window.Flags["ESP/MaxDistance"] or 500) * (Window.Flags["ESP/MaxDistance"] or 500)
        
        for model in pairs(Cache.Soldiers) do
            if not IsValidModel(model) then continue end
            
            if Window.Flags["ESP/TeamCheck"] and Cache.Friendlies[model] == true then
                continue
            end
            
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

local function IsDeadlineGame()
    local charactersFolder = Workspace:FindFirstChild("characters")
    if not charactersFolder then
        return false
    end
    
    local hasDeadlineStructure = false
    for _, child in pairs(charactersFolder:GetChildren()) do
        if child:IsA("Model") and child:FindFirstChild("humanoid_root_part") then
            hasDeadlineStructure = true
            break
        end
    end
    
    return hasDeadlineStructure
end

local function Initialize()
    if not IsDeadlineGame() then
        warn("Deadline script loaded but game structure doesn't match. This might not be Deadline.")
        Parvus.Utilities.UI:Push({
            Title = "Deadline",
            Description = "Game detection failed. Make sure you're in Deadline (ID: 12144402492)",
            Duration = 5
        })
        return
    end
    
    CharacterFolder = Workspace:WaitForChild("characters", 10)
    
    if not CharacterFolder then
        warn("Could not find characters folder")
        return
    end
    
    local Window = Parvus.Utilities.UI:Window({
        Name = "DEADLINE",
        Position = UDim2.new(0.5, -248, 0.5, -248)
    })
    
    getgenv().Window = Window
    
    local ESPTab = Window:Tab({Name = "ESP"}) do
        local ESPSettingsSection = ESPTab:Section({Name = "ESP Settings", Side = "Left"}) do
            ESPSettingsSection:Toggle({Name = "Enable ESP", Flag = "ESP/Enabled", Value = true})
            ESPSettingsSection:Toggle({Name = "Box ESP", Flag = "ESP/Box", Value = true})
            ESPSettingsSection:Dropdown({Name = "Box Style", Flag = "ESP/BoxStyle", List = {
                {Name = "Full", Mode = "Button", Value = true},
                {Name = "Corner", Mode = "Button"},
                {Name = "ThreeD", Mode = "Button"}
            }})
            ESPSettingsSection:Toggle({Name = "Box Fill", Flag = "ESP/BoxFill", Value = false})
            ESPSettingsSection:Toggle({Name = "Name", Flag = "ESP/Name", Value = true})
            ESPSettingsSection:Toggle({Name = "Distance", Flag = "ESP/Distance", Value = true})
            ESPSettingsSection:Toggle({Name = "Wall Check", Flag = "ESP/WallCheck", Value = false})
            ESPSettingsSection:Toggle({Name = "Closest Enemy", Flag = "ESP/ClosestEnemy", Value = false})
            ESPSettingsSection:Toggle({Name = "Skeleton", Flag = "ESP/Skeleton", Value = false})
            ESPSettingsSection:Slider({Name = "Skeleton Thickness", Flag = "ESP/SkeletonThickness", Min = 1, Max = 5, Value = 1.5, Precise = 1})
            ESPSettingsSection:Slider({Name = "Max Distance", Flag = "ESP/MaxDistance", Min = 500, Max = 3000, Value = 500, Step = 50})
            ESPSettingsSection:Toggle({Name = "Tracer", Flag = "ESP/Tracer", Value = false})
            ESPSettingsSection:Dropdown({Name = "Tracer Origin", Flag = "ESP/TracerOrigin", List = {
                {Name = "Bottom", Mode = "Button", Value = true},
                {Name = "Center", Mode = "Button"},
                {Name = "Top", Mode = "Button"}
            }})
            ESPSettingsSection:Toggle({Name = "Team Check", Flag = "ESP/TeamCheck", Value = true, Callback = function(Bool)
                ClearTeamCache()
            end})
        end
        
        local ColorSection = ESPTab:Section({Name = "Colors", Side = "Left"}) do
            ColorSection:Colorpicker({Name = "Enemy Color", Flag = "ESP/EnemyColor", Value = {1, 0.294, 0.333, 0, false}})
            ColorSection:Colorpicker({Name = "Friendly Color", Flag = "ESP/FriendlyColor", Value = {0.314, 0.706, 1, 0, false}})
            ColorSection:Colorpicker({Name = "Checking Color", Flag = "ESP/CheckingColor", Value = {0.588, 0.588, 0.588, 0, false}})
            ColorSection:Colorpicker({Name = "Tracer Color", Flag = "ESP/TracerColor", Value = {1, 0.549, 0.392, 0, false}})
            ColorSection:Colorpicker({Name = "Skeleton Color", Flag = "ESP/SkeletonColor", Value = {1, 1, 1, 0, false}})
            ColorSection:Colorpicker({Name = "Box Fill Color", Flag = "ESP/BoxFillColor", Value = {1, 0.294, 0.333, 0.15, false}})
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
    
    local AIMTab = Window:Tab({Name = "AIM"}) do
        local AimbotSection = AIMTab:Section({Name = "Aimbot Settings", Side = "Left"}) do
            AimbotSection:Toggle({Name = "Enable Aimbot", Flag = "AIM/Enabled", Value = false})
            AimbotSection:Toggle({Name = "Show FOV", Flag = "AIM/ShowFOV", Value = true})
            AimbotSection:Slider({Name = "FOV Size", Flag = "AIM/FOV", Min = 50, Max = 400, Value = 180, Step = 10})
            AimbotSection:Slider({Name = "Smoothness", Flag = "AIM/Smooth", Min = 0.05, Max = 0.5, Value = 0.18, Precise = 2})
            AimbotSection:Slider({Name = "Camera FOV", Flag = "AIM/CameraFOV", Min = 70, Max = 120, Value = 70, Step = 1})
            AimbotSection:Dropdown({Name = "Target Part", Flag = "AIM/TargetPart", List = {
                {Name = "Head", Mode = "Button", Value = true},
                {Name = "Torso", Mode = "Button"},
                {Name = "Root", Mode = "Button"}
            }})
            AimbotSection:Toggle({Name = "Team Check", Flag = "AIM/TeamCheck", Value = true})
            AimbotSection:Toggle({Name = "Prediction", Flag = "AIM/Prediction", Value = false})
            AimbotSection:Dropdown({Name = "Prediction Type", Flag = "AIM/PredictionType", List = {
                {Name = "Rifle", Mode = "Button", Value = true},
                {Name = "Sniper", Mode = "Button"},
                {Name = "Pistol", Mode = "Button"}
            }})
        end
        
        local PredictionSection = AIMTab:Section({Name = "Prediction", Side = "Right"}) do
            PredictionSection:Toggle({Name = "Show Prediction Dot", Flag = "AIM/PredictionDot", Value = true})
            PredictionSection:Slider({Name = "Dot Size", Flag = "AIM/PredictionDotSize", Min = 2, Max = 15, Value = 5, Step = 1})
            PredictionSection:Colorpicker({Name = "Dot Color", Flag = "AIM/PredictionDotColor", Value = {1, 1, 1, 0.3, false}})
        end
        
        local FOVSection = AIMTab:Section({Name = "FOV Circle", Side = "Right"}) do
            FOVSection:Colorpicker({Name = "FOV Color", Flag = "AIM/FOVColor", Value = {1, 0.294, 0.333, 0.7, false}})
        end
    end
    
    local OptionsTab = Window:Tab({Name = "Options"}) do
        local MenuSection = OptionsTab:Section({Name = "Menu", Side = "Left"}) do
            local UIToggle = MenuSection:Toggle({Name = "UI Enabled", Flag = "UI/Enabled", IgnoreFlag = true,
            Value = Window.Enabled, Callback = function(Bool) Window.Enabled = Bool end})
            UIToggle:Keybind({Value = "Insert", Flag = "UI/Keybind", IgnoreList = true, DoNotClear = true,
            Callback = function(Key, KeyDown)
                if KeyDown then
                    Window.Enabled = not Window.Enabled
                end
            end})
        end
        
        local ConfigSection = OptionsTab:Section({Name = "Config", Side = "Right"}) do
            local FolderName = "Varus/Deadline"
            if not isfolder("Varus") then makefolder("Varus") end
            if not isfolder(FolderName) then makefolder(FolderName) end
            if not isfolder(FolderName .. "\\Configs") then makefolder(FolderName .. "\\Configs") end
            
            local function UpdateConfigList()
                local configs = {}
                for _, configFile in pairs(listfiles(FolderName .. "\\Configs") or {}) do
                    local configName = configFile:gsub(FolderName .. "\\Configs\\", ""):gsub(".json", "")
                    configs[#configs + 1] = {
                        Name = configName,
                        Mode = "Button"
                    }
                end
                return configs
            end
            
            local ConfigDropdown = ConfigSection:Dropdown({Name = "Config", Flag = "Config/Selected", List = UpdateConfigList()})
            
            ConfigSection:Button({Name = "Save", Callback = function()
                local selected = Window.Flags["Config/Selected"]
                if selected and selected[1] then
                    Window:SaveConfig(FolderName, selected[1])
                else
                    Parvus.Utilities.UI:Push({
                        Title = "Config System",
                        Description = "Select Config First",
                        Duration = 3
                    })
                end
            end})
            
            ConfigSection:Button({Name = "Load", Callback = function()
                local selected = Window.Flags["Config/Selected"]
                if selected and selected[1] then
                    Window:LoadConfig(FolderName, selected[1])
                else
                    Parvus.Utilities.UI:Push({
                        Title = "Config System",
                        Description = "Select Config First",
                        Duration = 3
                    })
                end
            end})
            
            ConfigSection:Button({Name = "Delete", Callback = function()
                local selected = Window.Flags["Config/Selected"]
                if selected and selected[1] then
                    Window:DeleteConfig(FolderName, selected[1])
                    ConfigDropdown:SetList(UpdateConfigList())
                else
                    Parvus.Utilities.UI:Push({
                        Title = "Config System",
                        Description = "Select Config First",
                        Duration = 3
                    })
                end
            end})
            
            ConfigSection:Button({Name = "Refresh", Callback = function()
                ConfigDropdown:SetList(UpdateConfigList())
            end})
            
            local AutoLoadDivider = ConfigSection:Divider({Text = "AutoLoad Config"})
            ConfigSection:Button({Name = "Set AutoLoad Config", Callback = function()
                local selected = Window.Flags["Config/Selected"]
                if selected and selected[1] then
                    Window:AddToAutoLoad("Varus/Deadline", selected[1])
                    Parvus.Utilities.UI:Push({
                        Title = "Config System",
                        Description = "AutoLoad set to: " .. selected[1],
                        Duration = 3
                    })
                else
                    Parvus.Utilities.UI:Push({
                        Title = "Config System",
                        Description = "Select Config First",
                        Duration = 3
                    })
                end
            end})
        end
    end
    
    local autoLoadConfig = Window:GetAutoLoadConfig("Varus/Deadline")
    if autoLoadConfig then
        Window:LoadConfig("Varus/Deadline", autoLoadConfig)
    end
    
    local lastSaveTime = 0
    local saveInterval = 5
    Connections.AutoSave = RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastSaveTime > saveInterval then
            lastSaveTime = now
            local autoLoadConfig = Window:GetAutoLoadConfig("Varus/Deadline")
            if autoLoadConfig then
                pcall(function()
                    Window:SaveConfig("Varus/Deadline", autoLoadConfig)
                end)
            end
        end
    end)
    
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
        Cache.WallCheckResults = {}
        Cache.ClosestEnemy = nil
        ResetPool()
    end)
    
    Connections.CharacterRemoving = LocalPlayer.CharacterRemoving:Connect(function()
        ClearAllChams()
        Cache.Soldiers = {}
        Cache.Friendlies = {}
        Cache.FriendlyScores = {}
        Cache.ConfirmedEnemies = {}
        Cache.EnemyConfirmations = {}
        Cache.LastFriendlyUpdate = {}
        Cache.WallCheckResults = {}
        Cache.ClosestEnemy = nil
        ResetPool()
    end)
end

Initialize()
