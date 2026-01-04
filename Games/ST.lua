local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")


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
    end
    
    Parvus.Utilities:SettingsSection(Window, "RightShift", false)
end

Parvus.Utilities.InitAutoLoad(Window)
Parvus.Utilities:SetupWatermark(Window)
Parvus.Utilities.Drawing.SetupCursor(Window)
Parvus.Utilities.Drawing.SetupCrosshair(Window.Flags)

local tankHighlights = {}
local boxContainers = {}

local function debugPrint(message)
    print("[Tank ESP] " .. message)
end

local highlightedObjects = {
    ["Ammo rack"] = {
        color = Color3.fromRGB(255, 0, 0), -- Red
        fillTransparency = 0.5,
    },
    ["Fuel tank"] = {
        color = Color3.fromRGB(255, 165, 0), -- Orange
        fillTransparency = 0.5,
    },
    ["Barrel"] = {
        color = Color3.fromRGB(0, 0, 255), -- Blue
        fillTransparency = 0.5,
    },
    ["Hull crew"] = {
        color = Color3.fromRGB(160, 32, 240), -- Purple
        fillTransparency = 0.5,
    },
    ["Turret crew"] = {
        color = Color3.fromRGB(255, 0, 255), -- Magenta
        fillTransparency = 0.5,
    },
}

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
    
    clearTankHighlights(tank)
    tankHighlights[tank] = {}
    
    local main = tank:FindFirstChild("Main")
    if not main then return end
    
    local hitboxes = main:FindFirstChild("Hitboxes")
    if not hitboxes then return end
    
    local foundCount = 0
    local fillTransparency = Window.Flags["ESP/Tank/Transparency"] or 0.5
    
    for _, descendant in ipairs(hitboxes:GetDescendants()) do
        if (descendant:IsA("MeshPart") or descendant:IsA("BasePart")) then
            local partName = descendant.Name
            if highlightedObjects[partName] then
                local config = highlightedObjects[partName]
                local hl = createHighlight(descendant, config.color, fillTransparency)
                
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
    
    for i, edge in ipairs(edges) do
        local part = Instance.new("Part")
        part.Name = "Edge_" .. edge[1] .. "_" .. edge[2]
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.Material = Enum.Material.Neon
        part.Color = boxColor
        part.Transparency = 0
        part.Size = Vector3.new(0.3, 0.3, 1)
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
        math.clamp(boxSize.X, 5, 50),
        math.clamp(boxSize.Y, 3, 20),
        math.clamp(boxSize.Z, 5, 50)
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
                part.Size = Vector3.new(0.3, 0.3, len)
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
