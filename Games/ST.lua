local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local highlightedObjects = {
    ["Ammo rack"] = { color = Color3.fromRGB(255, 0, 0), fillTransparency = 0.5 },
    ["Fuel tank"] = { color = Color3.fromRGB(255, 165, 0), fillTransparency = 0.5 },
    ["Barrel"] = { color = Color3.fromRGB(0, 0, 255), fillTransparency = 0.5 },
    ["Hull crew"] = { color = Color3.fromRGB(160, 32, 240), fillTransparency = 0.5 },
    ["Turret crew"] = { color = Color3.fromRGB(255, 0, 255), fillTransparency = 0.5 },
}

local partFlagMap = {
    ["Ammo rack"] = "AmmoRack",
    ["Fuel tank"] = "FuelTank",
    ["Barrel"] = "Barrel",
    ["Hull crew"] = "HullCrew",
    ["Turret crew"] = "TurretCrew",
}

local function getFlagColor(flagName, defaultColor3)
    local data = Window and Window.Flags[flagName] or nil
    if type(data) == "table" and #data >= 3 then
        local r, g, b = data[1], data[2], data[3]
        -- Support both normalized (0..1) and 0..255 values
        if r > 1 or g > 1 or b > 1 then
            r = math.clamp(math.floor(r), 0, 255)
            g = math.clamp(math.floor(g), 0, 255)
            b = math.clamp(math.floor(b), 0, 255)
            return Color3.fromRGB(r, g, b)
        else
            r = math.clamp(math.floor(r * 255), 0, 255)
            g = math.clamp(math.floor(g * 255), 0, 255)
            b = math.clamp(math.floor(b * 255), 0, 255)
            return Color3.fromRGB(r, g, b)
        end
    elseif typeof(data) == "Color3" then
        return data
    else
        return defaultColor3
    end
end


local Window = Parvus.Utilities.UI:Window({
    Name = ("Varus Hub %s %s"):format(utf8.char(8212), Parvus.Game.Name),
    Position = UDim2.new(0.5, -173 * 3, 0.5, -173), 
    Size = UDim2.new(0, 346, 0, 346)
}) do

    local VisualsTab = Window:Tab({Name = "Tank ESP"}) do
        local VisualsSection = VisualsTab:Section({Name = "Highlights", Side = "Left"}) do
            VisualsSection:Toggle({
                Name = "Tank ESP Enabled", 
                Flag = "ESP/Tank/Enabled", 
                Value = true,
                Callback = function(Bool)
                    if not Bool then
                        for tank, _ in pairs(tankHighlights) do
                            clearTankHighlights(tank)
                            clearBox(tank)
                        end
                    else
                        applyAllESP()
                    end
                end
            })
            
            VisualsSection:Toggle({
                Name = "3D Box ESP", 
                Flag = "ESP/Tank/Box", 
                Value = true,
                Callback = function(Bool)
                    if not Bool then
                        for tank, folder in pairs(boxContainers) do
                            clearBox(tank)
                        end
                    else
                        applyAllESP()
                    end
                end
            })
            
            VisualsSection:Toggle({
                Name = "Hitbox Highlights", 
                Flag = "ESP/Tank/Hitbox", 
                Value = true,
                Callback = function(Bool)
                    if not Bool then
                        for tank, _ in pairs(tankHighlights) do
                            clearTankHighlights(tank)
                        end
                    else
                        applyAllESP()
                    end
                end
            })
            
            VisualsSection:Slider({
                Name = "Fill Transparency", 
                Flag = "ESP/Tank/Transparency", 
                Min = 0, 
                Max = 1, 
                Value = 0.5,
                Callback = function(Value)
                    applyAllESP()
                end
            })
            
            VisualsSection:Colorpicker({
                Name = "Box Color", 
                Flag = "ESP/Tank/BoxColor", 
                Value = {1, 1, 1, 0, false}
            })
            
            VisualsSection:Slider({
                Name = "Edge Thickness", 
                Flag = "ESP/Tank/Box/Thickness", 
                Min = 1, 
                Max = 10, 
                Value = 1,
                Callback = function(Value)
                    -- update boxes next frame
                    task.defer(applyAllESP)
                end
            })
        end
        
        local FilterSection = VisualsTab:Section({Name = "Filters", Side = "Right"}) do
            FilterSection:Toggle({
                Name = "Team Check", 
                Flag = "ESP/Tank/TeamCheck", 
                Value = true,
                Callback = function(Bool)
                    applyAllESP()
                end
            })
            
            FilterSection:Toggle({
                Name = "Distance Check", 
                Flag = "ESP/Tank/DistanceCheck", 
                Value = false,
                Callback = function(Bool)
                    applyAllESP()
                end
            })
            
            FilterSection:Slider({
                Name = "Distance", 
                Flag = "ESP/Tank/Distance", 
                Min = 25, 
                Max = 1000, 
                Value = 250, 
                Unit = "studs",
                Callback = function(Value)
                    applyAllESP()
                end
            })
        end
        
        local PartsSection = VisualsTab:Section({Name = "Parts", Side = "Right"}) do
            -- Create toggles + colorpickers based on highlightedObjects
            for displayName, cfg in pairs(highlightedObjects) do
                local flagId = partFlagMap[displayName]
                if not flagId then continue end
                local flagBase = ("ESP/Tank/Parts/%s"):format(flagId)
                PartsSection:Toggle({
                    Name = displayName .. " Enabled",
                    Flag = flagBase .. "/Enabled",
                    Value = true,
                    Callback = function() applyAllESP() end
                })

                local defaultColor = {cfg.color.R, cfg.color.G, cfg.color.B, 0, false}
                PartsSection:Colorpicker({
                    Name = displayName .. " Color",
                    Flag = flagBase .. "/Color",
                    Value = defaultColor,
                    Callback = function() applyAllESP() end
                })
            end
        end
    end
    
    Parvus.Utilities:SettingsSection(Window, "RightShift", false)
end

Parvus.Utilities.InitAutoLoad(Window)
Parvus.Utilities:SetupWatermark(Window)
Parvus.Utilities.Drawing.SetupCursor(Window)
Parvus.Utilities.Drawing.SetupCrosshair(Window.Flags)

do
    local LobbyTab = Window:Tab({Name = "Lobby"}) do
        local GameSection = LobbyTab:Section({Name = "Game", Side = "Left"}) do
            GameSection:Toggle({Name = "Enable Local Tank ESP", Flag = "ESP/Tank/Lobby/Game/Enabled", Value = false})
            GameSection:Toggle({Name = "3D Box", Flag = "ESP/Tank/Lobby/Game/Box", Value = true})
            GameSection:Toggle({Name = "Hitbox Highlights", Flag = "ESP/Tank/Lobby/Game/Hitbox", Value = true})
            GameSection:Slider({Name = "Fill Transparency", Flag = "ESP/Tank/Lobby/Game/Transparency", Min = 0, Max = 1, Value = 0.5, Callback = function() end})
            GameSection:Colorpicker({Name = "Box Color", Flag = "ESP/Tank/Lobby/Game/BoxColor", Value = {1,1,1,0,false}})
            GameSection:Slider({Name = "Edge Thickness", Flag = "ESP/Tank/Lobby/Game/Box/Thickness", Min = 1, Max = 10, Value = 1})
        end

        local HangerSection = LobbyTab:Section({Name = "Hanger", Side = "Right"}) do
            HangerSection:Toggle({Name = "Enable Hanger ESP", Flag = "ESP/Tank/Lobby/Hanger/Enabled", Value = false})
            HangerSection:Toggle({Name = "3D Box", Flag = "ESP/Tank/Lobby/Hanger/Box", Value = true})
            HangerSection:Toggle({Name = "Hitbox Highlights", Flag = "ESP/Tank/Lobby/Hanger/Hitbox", Value = true})
            HangerSection:Slider({Name = "Fill Transparency", Flag = "ESP/Tank/Lobby/Hanger/Transparency", Min = 0, Max = 1, Value = 0.5})
            HangerSection:Colorpicker({Name = "Box Color", Flag = "ESP/Tank/Lobby/Hanger/BoxColor", Value = {1,1,1,0,false}})
            HangerSection:Slider({Name = "Edge Thickness", Flag = "ESP/Tank/Lobby/Hanger/Box/Thickness", Min = 1, Max = 10, Value = 1})
        end

        local LobbyParts = LobbyTab:Section({Name = "Parts", Side = "Left"}) do
            for displayName, cfg in pairs(highlightedObjects) do
                local flagId = partFlagMap[displayName]
                if not flagId then continue end
                local flagBase = ("ESP/Tank/Lobby/Parts/%s"):format(flagId)
                LobbyParts:Toggle({Name = displayName .. " Enabled", Flag = flagBase .. "/Enabled", Value = true})
                LobbyParts:Colorpicker({Name = displayName .. " Color", Flag = flagBase .. "/Color", Value = {cfg.color.R, cfg.color.G, cfg.color.B, 0, false}})
            end
        end
    end
end

local tankHighlights = {}
local boxContainers = {}

local function debugPrint(message)
    print("[Tank ESP] " .. message)
end


-- (partFlagMap and getFlagColor defined earlier)

local function createHighlight(object, color, fillTransparency)
    if not object:IsA("BasePart") and not object:IsA("MeshPart") then return nil end
    
    local highlight = Instance.new('BoxHandleAdornment')
    highlight.Adornee = object
    highlight.AlwaysOnTop = true
    highlight.ZIndex = 5
    highlight.Size = object.Size + Vector3.new(0.1, 0.1, 0.1)
    highlight.Color3 = color
    highlight.Transparency = fillTransparency
    highlight.Parent = object
    
    return highlight
end

local function getAllTanks()
    local tanks = {}
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            local owner = child:FindFirstChild("Owner")
            if owner and owner:IsA("StringValue") and owner.Value ~= "" then
                table.insert(tanks, child)
            end
        end
    end
    return tanks
end

local function getPlayerFromTank(tank)
    local owner = tank:FindFirstChild("Owner")
    if not owner or not owner:IsA("StringValue") then 
        return nil 
    end
    
    local ownerUsername = owner.Value
    if not ownerUsername or ownerUsername == "" then 
        return nil 
    end
    
    return Players:FindFirstChild(ownerUsername)
end

local function isEnemyTank(tank)
    local tankOwner = getPlayerFromTank(tank)
    
    if not tankOwner then return false end
    if tankOwner == LocalPlayer then return false end
    
    if Window.Flags["ESP/Tank/DistanceCheck"] then
        local distance = Window.Flags["ESP/Tank/Distance"] or 250
        local main = tank:FindFirstChild("Main")
        if main then
            local playerPos = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if playerPos then
                if (playerPos.Position - main.Position).Magnitude > distance then
                    return false
                end
            end
        end
    end
    
    if Window.Flags["ESP/Tank/TeamCheck"] then
        local myTeam = LocalPlayer.Team
        local theirTeam = tankOwner.Team
        
        if not myTeam or not theirTeam then return false end
        
        return myTeam.Name ~= theirTeam.Name
    end
    
    return true
end

local function clearTankHighlights(tank)
    if tankHighlights[tank] then
        for _, hl in pairs(tankHighlights[tank]) do
            if hl and hl.Parent then 
                hl:Destroy() 
            end
        end
        tankHighlights[tank] = nil
    end
end

local function highlightEnemyTank(tank)
    if not Window.Flags["ESP/Tank/Enabled"] or not Window.Flags["ESP/Tank/Hitbox"] then 
        clearTankHighlights(tank)
        return 
    end
    if not isEnemyTank(tank) then 
        clearTankHighlights(tank)
        return 
    end
    local fillTransparency = Window.Flags["ESP/Tank/Transparency"] or 0.5

    if tankHighlights[tank] then
        -- update colors/transparency of existing highlights
        for _, hl in pairs(tankHighlights[tank]) do
            if hl and hl.Adornee then
                local partName = hl.Adornee.Name
                local cfg = highlightedObjects[partName]
                if cfg then
                    local flagId = partFlagMap[partName]
                    local color = cfg.color
                    if flagId then
                        color = getFlagColor(("ESP/Tank/Parts/%s/Color"):format(flagId), cfg.color)
                    end
                    hl.Color3 = color
                    hl.Transparency = fillTransparency
                end
            end
        end
        return
    end
    tankHighlights[tank] = {}
    
    local main = tank:FindFirstChild("Main")
    if not main then return end
    
    local hitboxes = main:FindFirstChild("Hitboxes")
    if not hitboxes then return end
    
    local foundCount = 0
    
    for _, descendant in ipairs(hitboxes:GetDescendants()) do
        if (descendant:IsA("MeshPart") or descendant:IsA("BasePart")) then
            local partName = descendant.Name
            if highlightedObjects[partName] then
                local config = highlightedObjects[partName]
                local flagId = partFlagMap[partName]
                local enabledFlag = flagId and Window.Flags[("ESP/Tank/Parts/%s/Enabled"):format(flagId)]
                if enabledFlag == false then
                    continue
                end

                local color = config.color
                if flagId then
                    color = getFlagColor(("ESP/Tank/Parts/%s/Color"):format(flagId), config.color)
                end

                local hl = createHighlight(descendant, color, fillTransparency)

                if hl then 
                    table.insert(tankHighlights[tank], hl)
                    foundCount = foundCount + 1
                end
            end
        end
    end
    
    if foundCount > 0 then
        debugPrint("  ✓ Highlighted " .. foundCount .. " parts in " .. tank.Name)
    end
end

local function clearBox(tank)
    if boxContainers[tank] then
        boxContainers[tank]:Destroy()
        boxContainers[tank] = nil
    end
end

local function create3DBox(tank)
    if not Window.Flags["ESP/Tank/Enabled"] or not Window.Flags["ESP/Tank/Box"] then return end
    if boxContainers[tank] then return end
    if not isEnemyTank(tank) then return end
    
    local folder = Instance.new("Folder")
    folder.Name = "TankBoxESP"
    folder.Parent = Workspace.CurrentCamera
    
    local edges = {
        {1,2}, {2,3}, {3,4}, {4,1},
        {5,6}, {6,7}, {7,8}, {8,5},
        {1,5}, {2,6}, {3,7}, {4,8},
    }
    
    local boxColorData = Window.Flags["ESP/Tank/BoxColor"] or {1, 1, 1, 0, false}
    local boxColor = Color3.fromRGB(
        math.floor(boxColorData[1] * 255),
        math.floor(boxColorData[2] * 255),
        math.floor(boxColorData[3] * 255)
    )
    
    local thicknessVal = (Window.Flags["ESP/Tank/Box/Thickness"] or 1) * 0.3
    for i, edge in ipairs(edges) do
        local part = Instance.new("Part")
        part.Name = "Edge_" .. edge[1] .. "_" .. edge[2]
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.Material = Enum.Material.Neon
        part.Color = boxColor
        part.Transparency = 0
        part.Size = Vector3.new(thicknessVal, thicknessVal, 1)
        part.CastShadow = false
        part.Massless = true
        part.Parent = folder
    end
    
    boxContainers[tank] = folder
end

local function update3DBox(tank, folder)
    if not tank.Parent or not isEnemyTank(tank) then
        clearBox(tank)
        return
    end
    
    local main = tank:FindFirstChild("Main")
    local hull = main and main:FindFirstChild("Hull")
    local boxModel = hull or main or tank
    
    local success, boxCF, boxSize = pcall(boxModel.GetBoundingBox, boxModel)
    if not success then return end
    
    boxSize = Vector3.new(
        math.clamp(boxSize.X, 1, 200),
        math.clamp(boxSize.Y, 1, 200),
        math.clamp(boxSize.Z, 1, 200)
    )
    
    local half = boxSize / 2
    
    local corners = {
        Vector3.new(-half.X, -half.Y, -half.Z),
        Vector3.new( half.X, -half.Y, -half.Z),
        Vector3.new( half.X,  half.Y, -half.Z),
        Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new( half.X, -half.Y,  half.Z),
        Vector3.new( half.X,  half.Y,  half.Z),
        Vector3.new(-half.X,  half.Y,  half.Z),
    }
    
    local edges = {
        {1,2}, {2,3}, {3,4}, {4,1},
        {5,6}, {6,7}, {7,8}, {8,5},
        {1,5}, {2,6}, {3,7}, {4,8},
    }
    
    for i, edge in ipairs(edges) do
        local part = folder:FindFirstChild("Edge_" .. edge[1] .. "_" .. edge[2])
        if part then
            local a = corners[edge[1]]
            local b = corners[edge[2]]
            local p1 = boxCF * a
            local p2 = boxCF * b
            local mid = (p1 + p2) / 2
            local dir = p2 - p1
            local len = dir.Magnitude
            if len > 0 then
                local thicknessVal = (Window.Flags["ESP/Tank/Box/Thickness"] or 1) * 0.3
                part.Size = Vector3.new(thicknessVal, thicknessVal, len)
                part.CFrame = CFrame.lookAt(mid, mid + dir.Unit)
            end
        end
    end
end

local function applyAllESP()
    local tanks = getAllTanks()
    
    debugPrint("=== Scanning for tanks ===")
    debugPrint("Found " .. #tanks .. " tanks")
    
    local myTeam = LocalPlayer.Team
    if myTeam then
        debugPrint("LocalPlayer team: " .. myTeam.Name)
    else
        debugPrint("LocalPlayer has NO TEAM")
    end
    
    local validTanks = {}
    local enemyCount = 0
    
    for _, tank in ipairs(tanks) do
        validTanks[tank] = true
        
        local owner = getPlayerFromTank(tank)
        if owner then
            local ownerTeam = owner.Team
            local ownerTeamName = ownerTeam and ownerTeam.Name or "NO TEAM"
            local isEnemy = isEnemyTank(tank)
            
            debugPrint("Tank: " .. tank.Name .. " | Owner: " .. owner.Name .. " | Team: " .. ownerTeamName .. " | Enemy: " .. tostring(isEnemy))
            
            if isEnemy then
                enemyCount = enemyCount + 1
                highlightEnemyTank(tank)
                create3DBox(tank)
            else
                clearTankHighlights(tank)
                clearBox(tank)
            end
        end
    end
    
    debugPrint("=== Highlighted " .. enemyCount .. " enemies ===")
    
    for tank, _ in pairs(tankHighlights) do
        if not validTanks[tank] then
            clearTankHighlights(tank)
        end
    end
    
    for tank, folder in pairs(boxContainers) do
        if not validTanks[tank] then
            clearBox(tank)
        end
    end
end

local localHighlights = {}
local localBoxContainers = {}
local hangerHighlights = {}
local hangerBoxContainers = {}

local function getLocalTank()
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            local owner = child:FindFirstChild("Owner")
            if owner and owner:IsA("StringValue") and owner.Value == LocalPlayer.Name then
                return child
            end
        end
    end
    return nil
end

local function create3DBoxForModel(model, containersTable, flagsPrefix)
    if containersTable[model] then return end

    local folder = Instance.new("Folder")
    folder.Name = "TankBoxESP"
    folder.Parent = Workspace.CurrentCamera

    local edges = {
        {1,2}, {2,3}, {3,4}, {4,1},
        {5,6}, {6,7}, {7,8}, {8,5},
        {1,5}, {2,6}, {3,7}, {4,8},
    }

    local boxColorData = Window.Flags[flagsPrefix .. "/BoxColor"] or {1,1,1,0,false}
    local boxColor = Color3.fromRGB(math.floor(boxColorData[1]*255), math.floor(boxColorData[2]*255), math.floor(boxColorData[3]*255))
    local thicknessVal = (Window.Flags[flagsPrefix .. "/Box/Thickness"] or 1) * 0.3

    for i, edge in ipairs(edges) do
        local part = Instance.new("Part")
        part.Name = "Edge_" .. edge[1] .. "_" .. edge[2]
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.Material = Enum.Material.Neon
        part.Color = boxColor
        part.Transparency = 0
        part.Size = Vector3.new(thicknessVal, thicknessVal, 1)
        part.CastShadow = false
        part.Massless = true
        part.Parent = folder
    end

    containersTable[model] = folder
end

local function update3DBoxForModel(model, folder, flagsPrefix)
    if not model or not model.Parent then
        if folder and folder.Parent then folder:Destroy() end
        return
    end

    local main = model:FindFirstChild("Main")
    local hull = main and main:FindFirstChild("Hull")
    local boxModel = hull or main or model

    local success, boxCF, boxSize = pcall(boxModel.GetBoundingBox, boxModel)
    if not success then return end

    boxSize = Vector3.new(
        math.clamp(boxSize.X, 1, 200),
        math.clamp(boxSize.Y, 1, 200),
        math.clamp(boxSize.Z, 1, 200)
    )

    local half = boxSize / 2
    local corners = {
        Vector3.new(-half.X, -half.Y, -half.Z),
        Vector3.new( half.X, -half.Y, -half.Z),
        Vector3.new( half.X,  half.Y, -half.Z),
        Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new( half.X, -half.Y,  half.Z),
        Vector3.new( half.X,  half.Y,  half.Z),
        Vector3.new(-half.X,  half.Y,  half.Z),
    }

    local edges = {
        {1,2}, {2,3}, {3,4}, {4,1},
        {5,6}, {6,7}, {7,8}, {8,5},
        {1,5}, {2,6}, {3,7}, {4,8},
    }

    for i, edge in ipairs(edges) do
        local part = folder:FindFirstChild("Edge_" .. edge[1] .. "_" .. edge[2])
        if part then
            local a = corners[edge[1]]
            local b = corners[edge[2]]
            local p1 = boxCF * a
            local p2 = boxCF * b
            local mid = (p1 + p2) / 2
            local dir = p2 - p1
            local len = dir.Magnitude
            if len > 0 then
                local thicknessVal = (Window.Flags[flagsPrefix .. "/Box/Thickness"] or 1) * 0.3
                part.Size = Vector3.new(thicknessVal, thicknessVal, len)
                part.CFrame = CFrame.lookAt(mid, mid + dir.Unit)
            end
        end
    end
end

local function highlightModelParts(model, highlightsTable, partsPrefix, transparencyFlagPrefix)
    if not model or not model.Parent then return end
    local main = model:FindFirstChild("Main") if not main then return end
    local hitboxes = main:FindFirstChild("Hitboxes") if not hitboxes then return end

    local fillTransparency = Window.Flags[transparencyFlagPrefix] or 0.5

    if highlightsTable[model] then
        -- update existing highlights' colors/transparency
        for _, hl in pairs(highlightsTable[model]) do
            if hl and hl.Adornee then
                local partName = hl.Adornee.Name
                local cfg = highlightedObjects[partName]
                if cfg then
                    local flagId = partFlagMap[partName]
                    local color = cfg.color
                    if flagId then
                        color = getFlagColor(partsPrefix .. "/" .. flagId .. "/Color", cfg.color)
                    end
                    hl.Color3 = color
                    hl.Transparency = fillTransparency
                end
            end
        end
        return
    end

    highlightsTable[model] = {}
    for _, descendant in ipairs(hitboxes:GetDescendants()) do
        if (descendant:IsA("MeshPart") or descendant:IsA("BasePart")) then
            local partName = descendant.Name
            local cfg = highlightedObjects[partName]
            if not cfg then continue end
            local flagId = partFlagMap[partName]
            local enabled = true
            if flagId then enabled = Window.Flags[partsPrefix .. "/" .. flagId .. "/Enabled"] end
            if enabled == false then continue end
            local color = cfg.color
            if flagId then color = getFlagColor(partsPrefix .. "/" .. flagId .. "/Color", cfg.color) end
            local hl = createHighlight(descendant, color, fillTransparency)
            if hl then table.insert(highlightsTable[model], hl) end
        end
    end
end

-- Hanger model lookup helper
local function getHangerModels()
    local out = {}
    if not Workspace:FindFirstChild("Ignore") then return out end
    local ig = Workspace.Ignore
    for _, child in pairs(ig:GetChildren()) do
        if child and child:IsA("Model") and child:FindFirstChild("Main") and child.Main:FindFirstChild("Hitboxes") then
            table.insert(out, child)
        end
    end
    return out
end


local function validateESP()
    for tank, _ in pairs(tankHighlights) do
        if not tank or not tank.Parent or not isEnemyTank(tank) then
            clearTankHighlights(tank)
            clearBox(tank)
        end
    end
end

Workspace.ChildAdded:Connect(function(child)
    task.wait(0.5) 
    if child:IsA("Model") and child:FindFirstChild("Owner") then
        local owner = getPlayerFromTank(child)
        if owner and isEnemyTank(child) then
            debugPrint("New enemy tank detected: " .. child.Name)
            highlightEnemyTank(child)
            create3DBox(child)
        end
    end
end)

RunService.RenderStepped:Connect(function()
    for tank, folder in pairs(boxContainers) do
        if folder and folder.Parent then
            update3DBox(tank, folder)
        end
    end
    for tank, folder in pairs(localBoxContainers) do
        if folder and folder.Parent then
            update3DBoxForModel(tank, folder, "ESP/Tank/Lobby/Game")
        end
    end
    for model, folder in pairs(hangerBoxContainers) do
        if folder and folder.Parent then
            update3DBoxForModel(model, folder, "ESP/Tank/Lobby/Hanger")
        end
    end
    
    validateESP()
end)

task.spawn(function()
    while true do
        task.wait(3)
        applyAllESP()
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        validateESP()
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local enabled = Window.Flags["ESP/Tank/Lobby/Game/Enabled"]
        local tank = getLocalTank()
        if not enabled then
            -- destroy all local highlights and boxes
            for m, list in pairs(localHighlights) do
                for _, hl in pairs(list) do if hl and hl.Parent then hl:Destroy() end end
                localHighlights[m] = nil
            end
            for m, f in pairs(localBoxContainers) do
                if f and f.Parent then f:Destroy() end
                localBoxContainers[m] = nil
            end
        elseif not tank then
            -- no local tank found; ensure cleared
            for m, list in pairs(localHighlights) do
                for _, hl in pairs(list) do if hl and hl.Parent then hl:Destroy() end end
                localHighlights[m] = nil
            end
            for m, f in pairs(localBoxContainers) do
                if f and f.Parent then f:Destroy() end
                localBoxContainers[m] = nil
            end
        else
            if Window.Flags["ESP/Tank/Lobby/Game/Hitbox"] then
                highlightModelParts(tank, localHighlights, "ESP/Tank/Lobby/Parts", "ESP/Tank/Lobby/Game/Transparency")
            end
            if Window.Flags["ESP/Tank/Lobby/Game/Box"] then
                create3DBoxForModel(tank, localBoxContainers, "ESP/Tank/Lobby/Game")
            else
                if localBoxContainers[tank] then localBoxContainers[tank]:Destroy() localBoxContainers[tank] = nil end
            end
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        local enabled = Window.Flags["ESP/Tank/Lobby/Hanger/Enabled"]
        local models = getHangerModels()
        if not enabled or #models == 0 then
            -- clear all hanger highlights/boxes
            for m, list in pairs(hangerHighlights) do
                for _, hl in pairs(list) do if hl and hl.Parent then hl:Destroy() end end
                hangerHighlights[m] = nil
            end
            for m, f in pairs(hangerBoxContainers) do
                if f and f.Parent then f:Destroy() end
                hangerBoxContainers[m] = nil
            end
        else
            for _, model in ipairs(models) do
                if Window.Flags["ESP/Tank/Lobby/Hanger/Hitbox"] then
                    highlightModelParts(model, hangerHighlights, "ESP/Tank/Lobby/Parts", "ESP/Tank/Lobby/Hanger/Transparency")
                end
                if Window.Flags["ESP/Tank/Lobby/Hanger/Box"] then
                    create3DBoxForModel(model, hangerBoxContainers, "ESP/Tank/Lobby/Hanger")
                else
                    if hangerBoxContainers[model] then hangerBoxContainers[model]:Destroy() hangerBoxContainers[model] = nil end
                end
            end
            for m, _ in pairs(hangerBoxContainers) do
                if not table.find(models, m) then if hangerBoxContainers[m] then hangerBoxContainers[m]:Destroy() end hangerBoxContainers[m] = nil end
            end
            for m, _ in pairs(hangerHighlights) do
                if not table.find(models, m) then
                    for _, hl in pairs(hangerHighlights[m]) do if hl and hl.Parent then hl:Destroy() end end
                    hangerHighlights[m] = nil
                end
            end
        end
    end
end)

task.wait(1.5)
applyAllESP()
task.spawn(function()
    while true do
        task.wait(3)
        applyAllESP()
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        validateESP()
    end
end)
