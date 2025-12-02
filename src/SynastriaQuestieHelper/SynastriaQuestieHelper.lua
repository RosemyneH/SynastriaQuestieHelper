local addonName, addonTable = ...
local SynastriaQuestieHelper = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local SynastriaCoreLib = LibStub("SynastriaCoreLib-1.0", true)

-- Constants
local CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM"

-- State
SynastriaQuestieHelper.quests = {}
SynastriaQuestieHelper.totalQuestCount = 0
SynastriaQuestieHelper.isScanning = false

function SynastriaQuestieHelper:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SynastriaQuestieHelperDB", {
        profile = {
            hideCompleted = true, -- Hide completed quests by default
            framePos = {}, -- Store frame position and size
        },
    }, true)

    self:RegisterChatCommand("synastriaquestiehelper", "OnSlashCommand")

    -- Minimap Button (Simple implementation since LibDBIcon is missing)
    self:CreateMinimapButton()
end

function SynastriaQuestieHelper:CreateMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local dataObj
    
    if LDB then
        dataObj = LDB:NewDataObject("SynastriaQuestieHelper", {
            type = "launcher",
            text = "SQH",
            icon = "Interface\\Icons\\Inv_Misc_QuestionMark",
            OnClick = function(_, button)
                if button == "LeftButton" then
                    self:ToggleUI()
                end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("Synastria Questie Helper")
                tooltip:AddLine("Click to toggle UI")
            end,
        })
    end

    -- Since we don't have LibDBIcon, we need a manual button if the user doesn't have a broker display.
    -- But usually LDB is enough if they have TitanPanel/Bazooka.
    -- The user specifically asked for a minimap button.
    -- I will create a simple frame for it.
    
    local mmBtn = CreateFrame("Button", "SynastriaQuestieHelperMinimapButton", Minimap)
    mmBtn:SetFrameStrata("MEDIUM")
    mmBtn:SetWidth(31)
    mmBtn:SetHeight(31)
    mmBtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT") -- Default position
    mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    local overlay = mmBtn:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    
    local icon = mmBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetTexture("Interface\\Icons\\Inv_Misc_QuestionMark")
    icon:SetPoint("CENTER", 0, 1)
    
    mmBtn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            self:ToggleUI()
        end
    end)
    
    mmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Synastria Questie Helper")
        GameTooltip:AddLine("Click to toggle UI")
        GameTooltip:Show()
    end)
    
    mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Dragging functionality
    mmBtn:RegisterForDrag("LeftButton")
    mmBtn:SetMovable(true)
    mmBtn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mmBtn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    
    self.minimapButton = mmBtn
end

function SynastriaQuestieHelper:OnEnable()
    -- Called when the addon is enabled
end

function SynastriaQuestieHelper:OnSlashCommand(input)
    if input:trim() == "toggle" then
        self:ToggleUI()
    elseif input:trim() == "reset" then
        self:ResetFramePosition()
    else
        self:Print("Usage: /synastriaquestiehelper [toggle, reset]")
    end
end

function SynastriaQuestieHelper:ResetFramePosition()
    self.db.profile.framePos = {}
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
    self:Print("Frame position reset. Open the UI again to see the default position.")
end

function SynastriaQuestieHelper:ScanQuests()
    if self.isScanning then
        self:Print("Scan already in progress.")
        return
    end
    
    -- Check cooldown
    local now = GetTime()
    if self.lastScanTime and (now - self.lastScanTime) < 10 then
        local remaining = math.ceil(10 - (now - self.lastScanTime))
        self:Print(string.format("Scan on cooldown. %d seconds remaining.", remaining))
        return
    end

    self.isScanning = true
    self.quests = {} -- Clear previous results
    self.totalQuestCount = 0 -- Reset total count
    self:RegisterEvent(CHAT_MSG_SYSTEM)
    
    -- Send the command to the server
    SendChatMessage(".findquest old", "SAY")
    
    self:Print("Scanning for quests...")
    
    -- Set a timeout to stop scanning if no response
    self:ScheduleTimer("StopScanning", 5)
end

function SynastriaQuestieHelper:StopScanning()
    self.isScanning = false
    self.lastScanTime = GetTime() -- Record scan time for cooldown
    self:UnregisterEvent(CHAT_MSG_SYSTEM)
    self:Print("Scan complete. Found " .. #self.quests .. " quests.")
    self:UpdateQuestList()
end

function SynastriaQuestieHelper:CHAT_MSG_SYSTEM(event, message)
    if not self.isScanning then return end

    -- Check for total quest count message
    -- Format: "Found 20 possible quests, showing 1 to 10:"
    local totalCount = message:match("Found (%d+) possible quests")
    if totalCount then
        self.totalQuestCount = tonumber(totalCount)
        self:UpdateQuestList()
        return
    end
    
    -- Parse individual quest messages
    -- Format seen: "1. [411] |cffffff00|Hquest:411:12|h[The Prodigal Lich Returns]|h|r"
    -- Regex: Match [ID] then find the name inside |h[Name]|h
    local questId, questName = message:match("%[(%d+)%].-|h%[(.-)%]|h")
    
    if questId and questName then
        table.insert(self.quests, {
            id = tonumber(questId),
            name = questName,
            reward = nil
        })
        self:UpdateQuestList()
    end
end

function SynastriaQuestieHelper:BuildQuestItemLookup()
    if self.questItemLookup then return end
    
    self.questItemLookup = {}
    
    -- Lazy-load QuestieDB
    if not self.QuestieDB and QuestieLoader then
        self.QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    end
    
    if not self.QuestieDB or not self.QuestieDB.ItemPointers then
        return
    end
    
    -- Build reverse lookup: questId -> {items that reward it}
    for itemId, _ in pairs(self.QuestieDB.ItemPointers) do
        -- Only check attunable items to reduce work
        if SynastriaCoreLib and SynastriaCoreLib.IsAttunable(itemId) then
            local questRewards = self.QuestieDB.QueryItemSingle(itemId, "questRewards")
            if questRewards and type(questRewards) == "table" then
                for _, rewardQuestId in ipairs(questRewards) do
                    if not self.questItemLookup[rewardQuestId] then
                        self.questItemLookup[rewardQuestId] = {}
                    end
                    table.insert(self.questItemLookup[rewardQuestId], {id = itemId, isChoice = false})
                end
            end
        end
    end
end

-- Get quest rewards by searching the item database
-- Returns a table of item IDs that list this quest as a reward
function SynastriaQuestieHelper:GetQuestRewardsFromItemDB(questId)
    -- Build lookup table once on first call
    if not self.questItemLookup then
        self:BuildQuestItemLookup()
    end
    
    return self.questItemLookup[questId] or {}
end

-- Get quest starter coordinates from Questie
function SynastriaQuestieHelper:GetQuestStarterCoords(questId)
    if not self.QuestieDB then return nil end
    
    -- Check NPCs first
    if self.QuestieDB.NPCPointers then
        for npcId in pairs(self.QuestieDB.NPCPointers) do
            local npcData = self.QuestieDB.QueryNPCSingle(npcId, "questStarts")
            if npcData and type(npcData) == "table" then
                -- Check if this NPC starts our quest
                for _, qId in ipairs(npcData) do
                    if qId == questId then
                        -- Found NPC that starts this quest, get spawns
                        local spawns = self.QuestieDB.QueryNPCSingle(npcId, "spawns")
                        if spawns and type(spawns) == "table" then
                            -- spawns is {[zoneId] = {{x,y}, {x,y}}}
                            for zoneId, coords in pairs(spawns) do
                                if coords and coords[1] and coords[1][1] and coords[1][2] then
                                    return coords[1][1], coords[1][2], zoneId
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- Check Objects if no NPC found
    if self.QuestieDB.ObjectPointers then
        for objId in pairs(self.QuestieDB.ObjectPointers) do
            local objData = self.QuestieDB.QueryObjectSingle(objId, "questStarts")
            if objData and type(objData) == "table" then
                -- Check if this object starts our quest
                for _, qId in ipairs(objData) do
                    if qId == questId then
                        -- Found object that starts this quest, get spawns
                        local spawns = self.QuestieDB.QueryObjectSingle(objId, "spawns")
                        if spawns and type(spawns) == "table" then
                            -- spawns is {[zoneId] = {{x,y}, {x,y}}}
                            for zoneId, coords in pairs(spawns) do
                                if coords and coords[1] and coords[1][1] and coords[1][2] then
                                    return coords[1][1], coords[1][2], zoneId
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    
    return nil
end

-- Get the full quest chain leading to this quest using Questie
function SynastriaQuestieHelper:GetQuestChain(questId)
    local chain = {}
    local current = questId
    local visited = {} -- Prevent infinite loops
    
    -- Lazy-load QuestieDB
    if not self.QuestieDB and QuestieLoader then
        self.QuestieDB = QuestieLoader:ImportModule("QuestieDB")
        if not self.QuestieDB then
            if not self.questieWarningShown then
                self:Print("Questie addon not detected or failed to load. Quest chains will not be displayed.")
                self.questieWarningShown = true
            end
            return chain
        end
    end
    
    while current and not visited[current] do
        visited[current] = true
        
        if self.QuestieDB and self.QuestieDB.GetQuest then
            local success, questData = pcall(function() return self.QuestieDB.GetQuest(current) end)
            
            if success and questData then
                -- preQuestSingle might be a table with quest IDs
                local preQuest = nil
                if questData.preQuestSingle then
                    if type(questData.preQuestSingle) == "table" then
                        preQuest = questData.preQuestSingle[1]
                    else
                        preQuest = questData.preQuestSingle
                    end
                elseif questData.preQuestGroup and type(questData.preQuestGroup) == "table" then
                    preQuest = questData.preQuestGroup[1]
                end
                
                table.insert(chain, 1, { 
                    id = current, 
                    name = questData.name or "Unknown"
                })
                current = preQuest
            else
                -- Failed to get quest data
                break
            end
        else
            break
        end
    end
    
    return chain
end

function SynastriaQuestieHelper:ToggleUI()
    if not self.frame then
        self:CreateUI()
        return -- Frame is shown on creation
    end
    
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function SynastriaQuestieHelper:CreateUI()
    local AceGUI = LibStub("AceGUI-3.0")
    if not AceGUI then return end
    
    -- Main Frame
    local frame = AceGUI:Create("Frame")
    local titleText = "Synastria Questie Helper"
    if self.totalQuestCount > 0 then
        titleText = string.format("Synastria Questie Helper (Showing %d/%d)", #self.quests, self.totalQuestCount)
    end
    frame:SetTitle(titleText)
    frame:SetCallback("OnClose", function(widget)
        -- Save position and size before closing
        local status = widget.status or widget.localstatus
        if status then
            self.db.profile.framePos = {
                width = status.width,
                height = status.height,
                top = status.top,
                left = status.left,
            }
        end
        AceGUI:Release(widget)
        self.frame = nil
    end)
    frame:SetLayout("Flow")
    
    -- Set frame strata lower so map appears on top
    frame.frame:SetFrameStrata("MEDIUM")
    
    -- Restore saved position/size or use defaults
    local pos = self.db.profile.framePos
    if pos and pos.width then
        frame:SetWidth(pos.width)
        frame:SetHeight(pos.height)
        if pos.top and pos.left then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
        end
    else
        frame:SetWidth(400)
        frame:SetHeight(400)
    end
    
    -- Make frame closable with ESC key
    _G["SynastriaQuestieHelperFrame"] = frame.frame
    tinsert(UISpecialFrames, "SynastriaQuestieHelperFrame")
    
    self.frame = frame
    
    -- Create scan button with AceGUI for consistent styling
    local scanBtn = AceGUI:Create("Button")
    scanBtn:SetText("Scan Zone")
    scanBtn:SetWidth(100)
    scanBtn:SetHeight(22)
    scanBtn:SetCallback("OnClick", function() self:ScanQuests() end)
    
    -- Position it manually next to close button
    scanBtn.frame:SetParent(frame.frame)
    scanBtn.frame:ClearAllPoints()
    scanBtn.frame:SetPoint("BOTTOMRIGHT", frame.frame, "BOTTOMRIGHT", -132, 16)
    scanBtn.frame:SetFrameLevel(frame.frame:GetFrameLevel() + 10)
    scanBtn.frame:Show()
    
    self.scanButton = scanBtn
    
    -- Scroll Frame for List
    local scrollContainer = AceGUI:Create("SimpleGroup")
    scrollContainer:SetFullWidth(true)
    scrollContainer:SetFullHeight(true)
    scrollContainer:SetLayout("Fill")
    frame:AddChild(scrollContainer)
    
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scrollContainer:AddChild(scroll)
    self.scroll = scroll
    
    self:UpdateQuestList()
end

-- Get quest status
function SynastriaQuestieHelper:GetQuestStatus(questId)
    -- Check if completed using Questie (if available)
    if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
        if Questie.db.char.complete[questId] then
            return "completed"
        end
    end
    
    -- Check if in quest log (accepted)
    -- In 3.3.5a, GetQuestLogTitle returns questID as the 9th parameter
    local numEntries, numQuests = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(i)
        if not isHeader and questID == questId then
            return "accepted"
        end
    end
    
    -- Check if prerequisites are met (if not, it's unavailable)
    local chain = self:GetQuestChain(questId)
    for i, chainQuest in ipairs(chain) do
        if chainQuest.id == questId then
            -- Found this quest in the chain, check if previous quest is completed
            if i > 1 then
                local prevQuest = chain[i-1]
                local prevStatus = "unknown"
                
                -- Check if previous quest is completed
                if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
                    if not Questie.db.char.complete[prevQuest.id] then
                        -- Previous quest not completed = this quest is unavailable
                        return "unavailable"
                    end
                end
            end
            break
        end
    end
    
    -- Not completed, not in log, prerequisites met = available
    return "available"
end

-- Helper to get rewards from quest log if quest is accepted
function SynastriaQuestieHelper:GetQuestLogRewards(questId)
    local rewards = {}
    
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, qId = GetQuestLogTitle(i)
        if not isHeader and qId == questId then
            -- Select this quest to query rewards
            SelectQuestLogEntry(i)
            
            -- Get choice rewards (player picks one)
            local numChoices = GetNumQuestLogChoices()
            for j = 1, numChoices do
                local name, texture, numItems, quality, isUsable = GetQuestLogChoiceInfo(j)
                if name then
                    -- Extract item ID from the link
                    local itemLink = GetQuestLogItemLink("choice", j)
                    if itemLink then
                        local itemId = tonumber(itemLink:match("item:(%d+)"))
                        if itemId and SynastriaCoreLib and SynastriaCoreLib.IsAttunable(itemId) then
                            table.insert(rewards, {id = itemId, isChoice = true})
                        end
                    end
                end
            end
            
            -- Get fixed rewards (player gets all)
            local numRewards = GetNumQuestLogRewards()
            for j = 1, numRewards do
                local name, texture, numItems, quality, isUsable = GetQuestLogRewardInfo(j)
                if name then
                    local itemLink = GetQuestLogItemLink("reward", j)
                    if itemLink then
                        local itemId = tonumber(itemLink:match("item:(%d+)"))
                        if itemId and SynastriaCoreLib and SynastriaCoreLib.IsAttunable(itemId) then
                            table.insert(rewards, {id = itemId, isChoice = false})
                        end
                    end
                end
            end
            
            break
        end
    end
    
    return rewards
end

function SynastriaQuestieHelper:UpdateQuestList()
    if not self.scroll then return end
    self.scroll:ReleaseChildren()
    
    -- Update frame title with quest count
    if self.frame then
        local titleText = "Synastria Questie Helper"
        if self.totalQuestCount > 0 then
            titleText = string.format("Synastria Questie Helper (Showing %d/%d)", #self.quests, self.totalQuestCount)
        end
        self.frame:SetTitle(titleText)
    end
    
    local AceGUI = LibStub("AceGUI-3.0")
    
    for _, quest in ipairs(self.quests) do
        -- Get quest chain
        local chain = self:GetQuestChain(quest.id)
        
        -- If no chain found, create a single-item chain
        if #chain == 0 then
            chain = {{id = quest.id, name = quest.name}}
        end
        
        -- Get rewards for quests in the chain
        local chainRewards = {}
        for _, chainQuest in ipairs(chain) do
            -- Get rewards from quest log if accepted
            local logRewards = self:GetQuestLogRewards(chainQuest.id)
            -- Get rewards from item database
            local itemDBRewards = self:GetQuestRewardsFromItemDB(chainQuest.id)
            
            -- Merge rewards, preferring quest log data when available
            if logRewards and #logRewards > 0 then
                chainRewards[chainQuest.id] = logRewards
            elseif itemDBRewards and #itemDBRewards > 0 then
                chainRewards[chainQuest.id] = itemDBRewards
            end
        end
        
        -- Create simplified header (no collapse functionality)
        local headerLabel = AceGUI:Create("Label")
        local rewardCount = 0
        for _ in pairs(chainRewards) do rewardCount = rewardCount + 1 end
        
        -- Simplified header with reward count if applicable
        local headerText
        if rewardCount > 0 then
            headerText = string.format("%s (Chain: %d quests, %d with rewards)", quest.name, #chain, rewardCount)
        else
            headerText = string.format("%s (Chain: %d quests)", quest.name, #chain)
        end
        
        headerLabel:SetText(headerText)
        headerLabel:SetFullWidth(true)
        headerLabel:SetColor(1, 0.82, 0) -- Gold color for header
        headerLabel:SetFont(GameFontNormal:GetFont(), 14, "OUTLINE")
        self.scroll:AddChild(headerLabel)
        
        -- Always show chain (no collapse)
        for i, chainQuest in ipairs(chain) do
                local status = self:GetQuestStatus(chainQuest.id)
                
                -- Check if we should hide completed quests
                if not (self.db.profile.hideCompleted and status == "completed") then
                    local chainLabel = AceGUI:Create("Label")
                    
                    -- Use numbers for all quests in chain
                    local prefix = string.format("  %d. ", i)
                    
                    -- Add coordinates for available quests
                    local questText = chainQuest.name
                    if status == "available" then
                        local x, y, zoneId = self:GetQuestStarterCoords(chainQuest.id)
                        if x and y then
                            questText = string.format("%s (%.1f, %.1f)", chainQuest.name, x, y)
                        end
                    end
                    
                    chainLabel:SetText(prefix .. questText)
                    chainLabel:SetFullWidth(true)
                    
                    -- Color based on status
                    if status == "completed" then
                        chainLabel:SetColor(0.6, 0.6, 0.6) -- Light gray
                    elseif status == "accepted" then
                        chainLabel:SetColor(0, 1, 0) -- Green
                    elseif status == "available" then
                        chainLabel:SetColor(1, 1, 0) -- Yellow
                    else -- unavailable
                        chainLabel:SetColor(0.8, 0.4, 0.4) -- Muted red
                    end
                    
                    self.scroll:AddChild(chainLabel)
                    
                    -- Show rewards if this quest has any
                    local rewards = chainRewards[chainQuest.id]
                    if rewards and #rewards > 0 then
                        local rewardGroup = AceGUI:Create("SimpleGroup")
                        rewardGroup:SetLayout("Flow")
                        rewardGroup:SetFullWidth(true)
                        
                        for _, reward in ipairs(rewards) do
                            local itemIcon = AceGUI:Create("Icon")
                            local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(reward.id)
                            
                            if itemTexture then
                                itemIcon:SetImage(itemTexture)
                                itemIcon:SetImageSize(16, 16)
                                itemIcon:SetWidth(24)
                                
                                -- Set label for choice indicator
                                if reward.isChoice then
                                    itemIcon:SetLabel("[C]")
                                else
                                    itemIcon:SetLabel("")
                                end
                                
                                -- Hover shows tooltip
                                itemIcon:SetCallback("OnEnter", function(widget)
                                    GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                                    GameTooltip:SetHyperlink("item:" .. reward.id)
                                    GameTooltip:Show()
                                end)
                                
                                itemIcon:SetCallback("OnLeave", function()
                                    GameTooltip:Hide()
                                end)
                                
                                -- Click for item ref
                                itemIcon:SetCallback("OnClick", function(widget, _, button)
                                    if itemLink then
                                        SetItemRef("item:" .. reward.id, itemLink, button)
                                    end
                                end)
                            else
                                -- Loading placeholder
                                itemIcon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
                                itemIcon:SetImageSize(16, 16)
                                itemIcon:SetWidth(24)
                                itemIcon:SetLabel("[?]")
                            end
                            
                            rewardGroup:AddChild(itemIcon)
                        end
                        
                        self.scroll:AddChild(rewardGroup)
                    end
                end
            end
            
            -- Add spacing between chains
            local spacer = AceGUI:Create("Label")
            spacer:SetText(" ")
            spacer:SetFullWidth(true)
            self.scroll:AddChild(spacer)
    end
end
