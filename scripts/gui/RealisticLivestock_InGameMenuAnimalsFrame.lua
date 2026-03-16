local Log = RmLogging.getLogger("RLRM")

RealisticLivestock_InGameMenuAnimalsFrame = {}


local function computeAvgGenetics(animal)
    local genetics = animal.genetics
    if genetics == nil or type(genetics) ~= "table" then return 0 end
    local total = 0
    local count = 0
    for _, value in pairs(genetics) do
        if value ~= nil then
            total = total + value
            count = count + 1
        end
    end
    return count > 0 and (total / count) or 0
end


local function sortRawAnimals(a, b)
    local aDisease = a:getHasAnyDisease()
    local bDisease = b:getHasAnyDisease()
    if aDisease and not bDisease then return true end
    if bDisease and not aDisease then return false end

    local sortByGenetics = RLSettings.SETTINGS.sortByGenetics
    if sortByGenetics ~= nil and sortByGenetics.state == 2 then
        local aGen = computeAvgGenetics(a)
        local bGen = computeAvgGenetics(b)
        if aGen ~= bGen then return aGen > bGen end
    end

    return a.age < b.age
end


--- Resolve the animal object at the list's current selection indices.
--- Must be called while husbandrySubTypes/subTypeIndexToClusters still hold the
--- data that matches the list's selectedSectionIndex/selectedIndex.
local function getSelectedAnimal(frame)
    local list = frame.list
    local section = list.selectedSectionIndex
    local index = list.selectedIndex
    if section == nil or index == nil then return nil end

    local subTypes = frame.husbandrySubTypes
    if subTypes == nil or subTypes[section] == nil then return nil end

    local subType = subTypes[section]
    local animals = frame.subTypeIndexToClusters[subType]
    if animals == nil or animals[index] == nil then return nil end

    return animals[index]
end


--- Find an animal's (section, index) position in the current sorted data.
local function findAnimalPosition(frame, animal)
    if animal == nil then return nil, nil end

    for sectionIdx, subType in ipairs(frame.husbandrySubTypes) do
        local animals = frame.subTypeIndexToClusters[subType]
        if animals ~= nil then
            for animalIdx, candidate in ipairs(animals) do
                if RLAnimalUtil.compare(candidate, animal) then
                    return sectionIdx, animalIdx
                end
            end
        end
    end

    return nil, nil
end


function RealisticLivestock_InGameMenuAnimalsFrame:reloadList(superFunc)
    -- Save selected animal BEFORE superFunc rebuilds data in base order.
    -- After superFunc, the numeric selection index still points at the old
    -- position but a different animal may now occupy that slot.
    local selectedAnimal = getSelectedAnimal(self)

    superFunc(self)

    if self.husbandrySubTypes == nil or #self.husbandrySubTypes == 0 then return end

    if #self.husbandrySubTypes > 1 then
        table.sort(self.husbandrySubTypes)
    end

    for _, subTypeIndex in ipairs(self.husbandrySubTypes) do
        local animals = self.subTypeIndexToClusters[subTypeIndex]
        if animals ~= nil and #animals > 1 then
            table.sort(animals, sortRawAnimals)
        end
    end

    -- Pre-set list selection indices to the saved animal's new position BEFORE
    -- reloadData(). The list picks up these indices during reload, so we avoid
    -- a post-reload correction call and its scroll/selection-change side effects.
    local newSection, newIndex = findAnimalPosition(self, selectedAnimal)
    if newSection ~= nil then
        self.list.selectedSectionIndex = newSection
        self.list.selectedIndex = newIndex
        Log:trace("AnimalsFrame: pre-set selection to section %d index %d", newSection, newIndex)
    end

    self.list:reloadData()

    Log:debug("AnimalsFrame: reloadList sorted %d subTypes", #self.husbandrySubTypes)
end

InGameMenuAnimalsFrame.reloadList = Utils.overwrittenFunction(
    InGameMenuAnimalsFrame.reloadList,
    RealisticLivestock_InGameMenuAnimalsFrame.reloadList
)


function RealisticLivestock_InGameMenuAnimalsFrame:displayCluster(superFunc, animal, husbandry)

    if g_currentMission.isRunning or Platform.isMobile then

        local animalSystem = g_currentMission.animalSystem
        local subTypeIndex = animal:getSubTypeIndex()
        local age = animal:getAge()
        local visual = animalSystem:getVisualByAge(subTypeIndex, age)

        if visual ~= nil then

            local subType = animal:getSubType()

            local name = animal:getName()
            name = name ~= "" and (" (" .. name .. ")") or ""

            local displayName = RL_AnimalScreenBase.formatDisplayName(animal.uniqueId .. name, animal)
            self.animalDetailTypeNameText:setText(displayName)
            self.animalDetailTypeImage:setImageFilename(visual.store.imageFilename)

            local ageMonth = g_i18n:formatNumMonth(age)
            self.animalAgeText:setText(ageMonth)

            local animalInfo = husbandry:getAnimalInfos(animal)

            for a, b in ipairs(self.infoRow) do

                local row = animalInfo[a]
                b:setVisible(row ~= nil)

                if row ~= nil then
                    local valueText = row.valueText or g_i18n:formatVolume(row.value, 0, row.customUnitText)
                    self.infoLabel[a]:setText(row.title)
                    self.infoValue[a]:setText(valueText)
                    self:setStatusBarValue(self.infoStatusBar[a], row.ratio, row.invertedBar, row.disabled)
                end

            end

            local description = husbandry:getAnimalDescription(animal)
            self.detailDescriptionText:setText(description)

        end

    end

end

InGameMenuAnimalsFrame.displayCluster = Utils.overwrittenFunction(InGameMenuAnimalsFrame.displayCluster, RealisticLivestock_InGameMenuAnimalsFrame.displayCluster)



function RealisticLivestock_InGameMenuAnimalsFrame:populateCellForItemInSection(_, subTypeIndex, animalIndex, cell)

    local subType = self.husbandrySubTypes[subTypeIndex]
    local animal = self.subTypeIndexToClusters[subType][animalIndex]

    if g_currentMission.animalSystem:getVisualByAge(subType, animal:getAge()) ~= nil then
        local baseName = animal.uniqueId .. (animal:getName() == "" and "" or (" (" .. animal:getName() .. ")"))
        cell:getAttribute("name"):setText(RL_AnimalScreenBase.formatDisplayName(baseName, animal))
        cell:getAttribute("count"):setVisible(false)
    end

end

InGameMenuAnimalsFrame.populateCellForItemInSection = Utils.appendedFunction(InGameMenuAnimalsFrame.populateCellForItemInSection, RealisticLivestock_InGameMenuAnimalsFrame.populateCellForItemInSection)


-- Add RL_OPEN_ANIMAL_SCREEN to NAV_ACTIONS only while the animals frame is active,
-- so the R key doesn't interfere with other frames (e.g. RemoveContract in contracts frame).
function RealisticLivestock_InGameMenuAnimalsFrame:onFrameOpen()
    table.insert(Gui.NAV_ACTIONS, InputAction.RL_OPEN_ANIMAL_SCREEN)
end

InGameMenuAnimalsFrame.onFrameOpen = Utils.appendedFunction(
    InGameMenuAnimalsFrame.onFrameOpen,
    RealisticLivestock_InGameMenuAnimalsFrame.onFrameOpen
)

function RealisticLivestock_InGameMenuAnimalsFrame:onFrameClose()
    for i = #Gui.NAV_ACTIONS, 1, -1 do
        if Gui.NAV_ACTIONS[i] == InputAction.RL_OPEN_ANIMAL_SCREEN then
            table.remove(Gui.NAV_ACTIONS, i)
            break
        end
    end
end

InGameMenuAnimalsFrame.onFrameClose = Utils.appendedFunction(
    InGameMenuAnimalsFrame.onFrameClose,
    RealisticLivestock_InGameMenuAnimalsFrame.onFrameClose
)


function RealisticLivestock_InGameMenuAnimalsFrame:onUpdateMenuButtons()
    local selectedHusbandry = self.selectedHusbandry
    if selectedHusbandry == nil then return end

    table.insert(self.menuButtonInfo, {
        inputAction = InputAction.RL_OPEN_ANIMAL_SCREEN,
        text = g_i18n:getText("rl_ui_openAnimalScreen"),
        callback = function()
            AnimalScreen.show(selectedHusbandry, nil, false)
        end
    })
end

InGameMenuAnimalsFrame.updateMenuButtons = Utils.appendedFunction(
    InGameMenuAnimalsFrame.updateMenuButtons,
    RealisticLivestock_InGameMenuAnimalsFrame.onUpdateMenuButtons
)
