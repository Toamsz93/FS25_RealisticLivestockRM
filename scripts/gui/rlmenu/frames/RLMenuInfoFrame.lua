--[[
    RLMenuInfoFrame.lua
    RL Tabbed Menu - Info tab.

    Left-sidebar husbandry picker with dot indicators, multi-section
    SmoothList of animal cards, and right-hand detail pane.
]]

RLMenuInfoFrame = {}
local RLMenuInfoFrame_mt = Class(RLMenuInfoFrame, TabbedMenuFrameElement)

local Log = RmLogging.getLogger("RLRM")

local modDirectory = g_currentModDirectory

-- Status bar coloring deferred: see setStatusBarValue. Bars rely on the
-- fs25_animalSmallStatusBar profile default (green) until we work out the
-- correct color rules.

-- Genetics tier color map. Colors applied via setTextColor at runtime
-- against a neutral text profile.
RLMenuInfoFrame.GENETICS_COLOR = {
    infertile      = { 1.00, 0.00, 0.00, 1 },
    extremelyLow   = { 1.00, 0.00, 0.00, 1 },
    veryLow        = { 1.00, 0.20, 0.00, 1 },
    low            = { 1.00, 0.52, 0.00, 1 },
    average        = { 1.00, 1.00, 0.00, 1 },
    high           = { 0.52, 1.00, 0.00, 1 },
    veryHigh       = { 0.20, 1.00, 0.00, 1 },
    extremelyHigh  = { 0.00, 1.00, 0.00, 1 },
}

-- Reset color when a row's colorKey is unknown, so stale tier colors from
-- the previous selection can't bleed onto the new row.
RLMenuInfoFrame.GENETICS_COLOR_NEUTRAL = { 1.00, 1.00, 1.00, 1 }

-- Number of pre-allocated XML row slots per stack
RLMenuInfoFrame.NUM_CONDITION_ROWS = 5
RLMenuInfoFrame.NUM_FOOD_ROWS      = 5
RLMenuInfoFrame.NUM_STAT_ROWS      = 10
RLMenuInfoFrame.NUM_GENETICS_ROWS  = 6
RLMenuInfoFrame.NUM_DISEASE_ROWS   = 5
RLMenuInfoFrame.NUM_INPUT_ROWS     = 3
RLMenuInfoFrame.NUM_OUTPUT_ROWS    = 5

-- Mark uses MENU_EXTRA_1 (X), Castrate uses MENU_EXTRA_2 (C) to avoid
-- key conflicts with the TabbedMenu defaults on those same keys.
-- Other mutations use custom RL_* actions.

---Construct a new RLMenuInfoFrame instance. Called once by setupGui.
---@return table self
function RLMenuInfoFrame.new()
    local self = RLMenuInfoFrame:superClass().new(nil, RLMenuInfoFrame_mt)
    self.name = "RLMenuInfoFrame"

    self.sortedHusbandries = {}
    self.selectedHusbandry = nil
    self.items             = {}
    self.filters           = {}
    self.farmId            = nil

    self.sectionOrder      = {}
    self.itemsBySection    = {}
    self.titlesBySection   = {}

    self.selectedIdentity  = nil  -- { farmId, uniqueId, country }

    -- Track husbandry's animal type so we can clear filters on type change
    -- (cow filters reference fields a sheep doesn't have and would drop every row).
    self.activeAnimalTypeIndex = nil

    self.isFrameOpen = false

    self.hasCustomMenuButtons = true
    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.filterButtonInfo = {
        inputAction = InputAction.MENU_CANCEL,
        text = g_i18n:getText("rl_menu_info_filter_button"),
        callback = function() self:onClickFilter() end,
    }
    self.markButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("rl_ui_mark"),
        callback = function() self:onClickMark() end,
    }
    self.monitorButtonInfo = {
        inputAction = InputAction.RL_MONITOR,
        text = g_i18n:getText("rl_ui_applyMonitor"),
        callback = function() self:onClickMonitor() end,
    }
    self.renameButtonInfo = {
        inputAction = InputAction.RL_RENAME,
        text = g_i18n:getText("rl_ui_rename"),
        callback = function() self:onClickRename() end,
    }
    self.diseasesButtonInfo = {
        inputAction = InputAction.RL_DISEASES,
        text = g_i18n:getText("rl_diseases"),
        callback = function() self:onClickDiseases() end,
    }
    self.castrateButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("rl_ui_castrate"),
        callback = function() self:onClickCastrate() end,
    }
    self.inseminateButtonInfo = {
        inputAction = InputAction.RL_AI,
        text = g_i18n:getText("rl_ui_artificialInsemination"),
        callback = function() self:onClickInseminate() end,
    }
    self.menuButtonInfo = { self.backButtonInfo }

    return self
end

---Load the info frame XML and register it with g_gui so the host menu's
---FrameReference can resolve it.
function RLMenuInfoFrame.setupGui()
    local frame = RLMenuInfoFrame.new()
    g_gui:loadGui(
        Utils.getFilename("gui/rlmenu/infoFrame.xml", modDirectory),
        "RLMenuInfoFrame",
        frame,
        true
    )
    Log:debug("RLMenuInfoFrame.setupGui: registered")
end

--- Bind the SmoothList datasource/delegate. Must not mutate the element
--- tree here: this hook fires on both the frame-only load instance AND
--- the clone resolveFrameReference creates, and tree mutation on the
--- first instance leaves the clone without what it needs. Tree mutation
--- lives in `initialize()` below, called by the host menu on the clone.
function RLMenuInfoFrame:onGuiSetupFinished()
    RLMenuInfoFrame:superClass().onGuiSetupFinished(self)

    if self.animalList ~= nil then
        self.animalList:setDataSource(self)
        self.animalList:setDelegate(self)
    else
        Log:warning("RLMenuInfoFrame:onGuiSetupFinished: animalList element missing from XML")
    end
end

--- One-time per-clone setup. Called explicitly by RLMenu:setupMenuPages
--- after the page is registered.
function RLMenuInfoFrame:initialize()
    if self.subCategoryDotTemplate ~= nil then
        self.subCategoryDotTemplate:unlinkElement()
        FocusManager:removeElement(self.subCategoryDotTemplate)
    else
        Log:warning("RLMenuInfoFrame:initialize: subCategoryDotTemplate missing - dots will not render")
    end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

---Called by the Paging element when this tab becomes active.
function RLMenuInfoFrame:onFrameOpen()
    RLMenuInfoFrame:superClass().onFrameOpen(self)
    self.isFrameOpen = true

    -- refreshHusbandries owns chrome state for both populated and empty
    -- husbandry cases. Do NOT clearDetail here: refreshHusbandries auto-
    -- selects state 1, which fires onHusbandryChanged -> updatePenDisplay,
    -- and a trailing clearDetail would wipe the pen we just rendered.
    self:refreshHusbandries()
end

---Called by the Paging element when this tab is deactivated.
function RLMenuInfoFrame:onFrameClose()
    RLMenuInfoFrame:superClass().onFrameClose(self)
    self.isFrameOpen = false
end

-- =============================================================================
-- Husbandry selector
-- =============================================================================

--- Repopulate the husbandry selector + dot indicators for the player's farm.
function RLMenuInfoFrame:refreshHusbandries()
    local farmId = RLAnimalInfoService.getCurrentFarmId()
    self.farmId = farmId

    self.sortedHusbandries = RLAnimalQuery.listHusbandriesForFarm(farmId)
    Log:debug("RLMenuInfoFrame:refreshHusbandries: farmId=%s husbandries=%d",
        tostring(farmId), #self.sortedHusbandries)

    if self.subCategoryDotBox ~= nil then
        for i, dot in pairs(self.subCategoryDotBox.elements) do
            dot:delete()
            self.subCategoryDotBox.elements[i] = nil
        end
    end

    if #self.sortedHusbandries == 0 then
        if self.noHusbandriesText ~= nil then self.noHusbandriesText:setVisible(true) end
        if self.subCategoryDotBox ~= nil then self.subCategoryDotBox:setVisible(false) end
        if self.subCategorySelector ~= nil then self.subCategorySelector:setTexts({}) end
        self.selectedHusbandry = nil
        self.items = {}
        if self.animalList ~= nil then self.animalList:reloadData() end
        self:updateEmptyState()
        self:updateButtonVisibility()
        -- Hide pen + animal chrome on the empty path; in the populated
        -- branch onHusbandryChanged renders them via updatePenDisplay.
        self:updateMoneyDisplay()
        self:clearDetail()
        return
    end

    if self.noHusbandriesText ~= nil then self.noHusbandriesText:setVisible(false) end

    local names = {}
    for index, husbandry in ipairs(self.sortedHusbandries) do
        names[index] = RLAnimalQuery.formatHusbandryLabel(husbandry, index)

        if self.subCategoryDotTemplate ~= nil and self.subCategoryDotBox ~= nil then
            local dot = self.subCategoryDotTemplate:clone(self.subCategoryDotBox)
            local dotIndex = index
            function dot.getIsSelected()
                return self.subCategorySelector ~= nil
                    and self.subCategorySelector:getState() == dotIndex
            end
        end
    end

    if self.subCategoryDotBox ~= nil then
        self.subCategoryDotBox:invalidateLayout()
        self.subCategoryDotBox:setVisible(1 < #names)
    end

    if self.subCategorySelector ~= nil then
        self.subCategorySelector:setTexts(names)
        self.subCategorySelector:setState(1, true)
    else
        self:onHusbandryChanged(1)
    end
end

--- MultiTextOption onClick callback. Clears filters on animal-type change
--- so filter fields from the previous type can't reference missing data.
--- @param state number 1-based husbandry index
function RLMenuInfoFrame:onHusbandryChanged(state)
    if state == nil or state < 1 or state > #self.sortedHusbandries then return end

    self.selectedHusbandry = self.sortedHusbandries[state]
    local newTypeIndex
    if self.selectedHusbandry ~= nil and self.selectedHusbandry.getAnimalTypeIndex ~= nil then
        newTypeIndex = self.selectedHusbandry:getAnimalTypeIndex()
    end

    if self.activeAnimalTypeIndex ~= nil
        and newTypeIndex ~= nil
        and newTypeIndex ~= self.activeAnimalTypeIndex
        and next(self.filters) ~= nil then
        Log:debug("RLMenuInfoFrame:onHusbandryChanged: animal type changed (%s -> %s), clearing filters",
            tostring(self.activeAnimalTypeIndex), tostring(newTypeIndex))
        self.filters = {}
    end
    self.activeAnimalTypeIndex = newTypeIndex

    Log:debug("RLMenuInfoFrame:onHusbandryChanged: state=%d husbandry='%s'",
        state,
        (self.selectedHusbandry ~= nil and self.selectedHusbandry.getName ~= nil
            and self.selectedHusbandry:getName()) or "?")

    self:reloadAnimalList()
    self:updatePenDisplay()
    self:updateMoneyDisplay()
    -- Do NOT clearAnimalDetail() here. reloadAnimalList -> restoreSelection
    -- now actively seeds the animal column for the auto-selected first row
    -- A trailing clear would wipe what restoreSelection just rendered.
    -- The empty-husbandry case is handled inside restoreSelection itself.
end

---SmoothList delegate: fired when the user picks a different row.
---@param list table
---@param section number
---@param index number
function RLMenuInfoFrame:onListSelectionChanged(list, section, index)
    if list ~= self.animalList then return end
    if section == nil or index == nil then return end
    Log:trace("RLMenuInfoFrame:onListSelectionChanged: section=%d index=%d", section, index)

    local key = self.sectionOrder[section]
    if key == nil then
        self:clearAnimalDetail()
        return
    end
    local items = self.itemsBySection[key]
    if items == nil then
        self:clearAnimalDetail()
        return
    end
    local item = items[index]
    if item == nil or item.cluster == nil then
        self:clearAnimalDetail()
        return
    end

    self:updateAnimalDisplay(item.cluster)
    self:updateButtonVisibility()
end

-- =============================================================================
-- Animal list
-- =============================================================================

--- Requery the current husbandry, group into sections, refresh the SmoothList,
--- restore selection by (farmId, uniqueId, country) identity.
function RLMenuInfoFrame:reloadAnimalList()
    self:captureCurrentSelection()

    if self.selectedHusbandry == nil then
        self.items = {}
    else
        self.items = RLAnimalQuery.listAnimalsForHusbandry(self.selectedHusbandry, self.filters)
    end

    self.sectionOrder, self.itemsBySection, self.titlesBySection =
        RLAnimalQuery.buildSections(self.items)

    if self.animalList ~= nil then
        self.animalList:reloadData()
    end

    self:restoreSelection()
    self:updateEmptyState()
    self:updateButtonVisibility()
end

--- Capture the currently highlighted animal's identity so it can be re-selected
--- after the next reload.
function RLMenuInfoFrame:captureCurrentSelection()
    if self.animalList == nil then return end
    local section = self.animalList.selectedSectionIndex
    local index   = self.animalList.selectedIndex
    if section == nil or index == nil then return end

    local key = self.sectionOrder[section]
    if key == nil then return end
    local list = self.itemsBySection[key]
    if list == nil or index < 1 or index > #list then return end

    local item = list[index]
    if item == nil or item.cluster == nil then return end

    local cluster = item.cluster
    local country = ""
    if cluster.birthday ~= nil then country = cluster.birthday.country or "" end
    self.selectedIdentity = {
        farmId   = cluster.farmId or 0,
        uniqueId = cluster.uniqueId or 0,
        country  = country,
    }
end

--- Re-highlight the previously selected animal. Falls back to (1, 1) when
--- the previous animal is no longer present.
function RLMenuInfoFrame:restoreSelection()
    if self.animalList == nil then return end

    if #self.sectionOrder == 0 then
        self.selectedIdentity = nil
        -- Husbandry has no animals: explicitly clear the animal column so
        -- stale data from a previous husbandry doesn't linger on screen.
        self:clearAnimalDetail()
        return
    end

    local section, index
    if self.selectedIdentity ~= nil then
        section, index = RLAnimalQuery.findSectionedItemByIdentity(
            self.sectionOrder,
            self.itemsBySection,
            self.selectedIdentity.farmId,
            self.selectedIdentity.uniqueId,
            self.selectedIdentity.country
        )
    end

    if section == nil or index == nil then
        section, index = 1, 1
    end

    self.animalList:setSelectedItem(section, index, false, true)

    -- SmoothList:setSelectedItem is programmatic and does NOT fire
    -- onListSelectionChanged. Seed the animal column manually so the
    -- auto-selected first row populates the right pane on initial open.
    local key = self.sectionOrder[section]
    if key == nil then return end
    local items = self.itemsBySection[key]
    if items == nil then return end
    local item = items[index]
    if item ~= nil and item.cluster ~= nil then
        self:updateAnimalDisplay(item.cluster)
    end
end

-- =============================================================================
-- Empty state / buttons
-- =============================================================================

---Toggle empty-state text + list chrome based on the current data.
function RLMenuInfoFrame:updateEmptyState()
    local hasHusbandries = #self.sortedHusbandries > 0
    local hasItems = #self.items > 0

    if self.noAnimalsText ~= nil then
        self.noAnimalsText:setVisible(hasHusbandries and not hasItems)
    end
    if self.noHusbandriesText ~= nil then
        self.noHusbandriesText:setVisible(not hasHusbandries)
    end
    if self.animalList ~= nil then
        self.animalList:setVisible(hasItems)
    end
end

---Resolve the currently selected animal from the list on demand.
---@return table|nil
function RLMenuInfoFrame:getSelectedAnimal()
    if self.animalList == nil then return nil end
    local section = self.animalList.selectedSectionIndex
    local index   = self.animalList.selectedIndex
    if section == nil or index == nil then return nil end

    local key = self.sectionOrder[section]
    if key == nil then return nil end
    local items = self.itemsBySection[key]
    if items == nil then return nil end
    local item = items[index]
    if item == nil then return nil end
    return item.cluster
end

---Rebuild the footer button info. Back is always shown; Filter only when
---at least one husbandry is available to filter. Mutation buttons are
---added conditionally based on the currently selected animal.
function RLMenuInfoFrame:updateButtonVisibility()
    self.menuButtonInfo = { self.backButtonInfo }
    if #self.sortedHusbandries > 0 then
        table.insert(self.menuButtonInfo, self.filterButtonInfo)
    end

    local animal = self:getSelectedAnimal()
    if animal ~= nil then
        -- Mark — always shown, text toggles (mirrors AnimalScreen.lua:1852-1854)
        local isMarked = animal.getMarked ~= nil and animal:getMarked()
        self.markButtonInfo.text = g_i18n:getText(isMarked and "rl_ui_unmark" or "rl_ui_mark")
        table.insert(self.menuButtonInfo, self.markButtonInfo)

        -- Monitor — always shown, 3-state text + disabled (mirrors AnimalScreen.lua:1871-1873)
        local monitor = animal.monitor
        if monitor ~= nil then
            local monitorText = monitor.removed and "removing" or (monitor.active and "remove" or "apply")
            self.monitorButtonInfo.text = g_i18n:getText("rl_ui_" .. monitorText .. "Monitor")
            self.monitorButtonInfo.disabled = monitor.removed
        else
            self.monitorButtonInfo.text = g_i18n:getText("rl_ui_applyMonitor")
            self.monitorButtonInfo.disabled = false
        end
        table.insert(self.menuButtonInfo, self.monitorButtonInfo)

        -- Rename — always shown (mirrors AnimalScreen.lua:2044)
        table.insert(self.menuButtonInfo, self.renameButtonInfo)

        -- Diseases — always shown (mirrors AnimalScreen.lua:1614)
        table.insert(self.menuButtonInfo, self.diseasesButtonInfo)

        -- Castrate — males only, not chickens (mirrors AnimalScreen.lua:1856-1858)
        if animal.gender == "male" and animal.animalTypeIndex ~= AnimalType.CHICKEN then
            self.castrateButtonInfo.disabled = animal.isCastrated
            table.insert(self.menuButtonInfo, self.castrateButtonInfo)
        end

        -- Inseminate — females only, disabled per conditions (mirrors AnimalScreen.lua:1861-1868)
        if animal.gender == "female" then
            local cannotInseminate = animal.pregnancy ~= nil
                or animal.isPregnant
                or animal.insemination ~= nil
                or (animal.getSubType ~= nil
                    and animal.age < animal:getSubType().reproductionMinAgeMonth)
                or (animal.isParent and animal.monthsSinceLastBirth ~= nil
                    and animal.monthsSinceLastBirth <= 2)
            self.inseminateButtonInfo.disabled = cannotInseminate
            table.insert(self.menuButtonInfo, self.inseminateButtonInfo)
        end
    end

    -- DEBUG: log button count and each action for keybinding diagnosis
    Log:debug("RLMenuInfoFrame:updateButtonVisibility: %d buttons in menuButtonInfo", #self.menuButtonInfo)
    for i, info in ipairs(self.menuButtonInfo) do
        Log:trace("  button[%d]: action=%s text=%s disabled=%s",
            i, tostring(info.inputAction), tostring(info.text), tostring(info.disabled))
    end

    self:setMenuButtonInfoDirty()
end

---Refresh list rows, detail pane, and button bar after a mutation.
---Called by mutation handlers to ensure the UI reflects the new state.
function RLMenuInfoFrame:refreshAfterMutation()
    -- Reload list rows (mark tint, name text may have changed)
    if self.animalList ~= nil then
        self.animalList:reloadData()
    end
    -- Re-render the animal detail pane
    local animal = self:getSelectedAnimal()
    if animal ~= nil then
        Log:trace("RLMenuInfoFrame:refreshAfterMutation: re-rendering detail for farmId=%s uniqueId=%s",
            tostring(animal.farmId), tostring(animal.uniqueId))
        self:updateAnimalDisplay(animal)
    else
        Log:trace("RLMenuInfoFrame:refreshAfterMutation: no animal selected after reload")
    end
    -- Rebuild button bar (text, disabled states)
    self:updateButtonVisibility()
end

-- =============================================================================
-- Filter button
-- =============================================================================

---Open AnimalFilterDialog for the current husbandry's animals.
function RLMenuInfoFrame:onClickFilter()
    if self.selectedHusbandry == nil then return end
    if AnimalFilterDialog == nil or AnimalFilterDialog.show == nil then
        Log:warning("RLMenuInfoFrame:onClickFilter: AnimalFilterDialog unavailable")
        return
    end

    local animalTypeIndex
    if self.selectedHusbandry.getAnimalTypeIndex ~= nil then
        animalTypeIndex = self.selectedHusbandry:getAnimalTypeIndex()
    end

    Log:debug("RLMenuInfoFrame:onClickFilter: opening dialog for %d items, animalTypeIndex=%s",
        #self.items, tostring(animalTypeIndex))

    AnimalFilterDialog.show(self.items, animalTypeIndex, self.onFilterApplied, self, false)
end

---AnimalFilterDialog callback fired on OK. Stores filters and re-queries.
---@param filters table
---@param _items table unused; we re-query via reloadAnimalList
function RLMenuInfoFrame:onFilterApplied(filters, _items)
    Log:debug("RLMenuInfoFrame:onFilterApplied: %d filter(s) active",
        (filters ~= nil and #filters) or 0)
    self.filters = filters or {}
    self:reloadAnimalList()
end

-- =============================================================================
-- SmoothList data source / delegate
-- =============================================================================

---SmoothList data source: number of sections in the list.
---@param list table
---@return number
function RLMenuInfoFrame:getNumberOfSections(list)
    if list == self.animalList then return #self.sectionOrder end
    return 0
end

---SmoothList data source: title for the given section header cell.
---@param list table
---@param section number
---@return string|nil
function RLMenuInfoFrame:getTitleForSectionHeader(list, section)
    if list ~= self.animalList then return nil end
    local key = self.sectionOrder[section]
    return key and self.titlesBySection[key] or nil
end

---SmoothList data source: number of items in the given section.
---@param list table
---@param section number
---@return number
function RLMenuInfoFrame:getNumberOfItemsInSection(list, section)
    if list ~= self.animalList then return 0 end
    local key = self.sectionOrder[section]
    if key == nil then return 0 end
    local items = self.itemsBySection[key]
    return items ~= nil and #items or 0
end

---SmoothList delegate: populate one data cell from the item at (section, index).
---@param list table
---@param section number
---@param index number
---@param cell table
function RLMenuInfoFrame:populateCellForItemInSection(list, section, index, cell)
    if list ~= self.animalList then return end

    local key = self.sectionOrder[section]
    if key == nil then return end
    local items = self.itemsBySection[key]
    if items == nil then return end
    local item = items[index]
    if item == nil then return end

    local row = RLAnimalQuery.formatAnimalRow(item)

    -- Cell tint: disease red, marked orange, normal otherwise.
    if cell.setImageColor ~= nil then
        if row.tint == RLAnimalQuery.TINT_DISEASE then
            cell:setImageColor(GuiOverlay.STATE_NORMAL, 1, 0.08, 0)
        elseif row.tint == RLAnimalQuery.TINT_MARKED then
            cell:setImageColor(GuiOverlay.STATE_NORMAL, 1, 0.2, 0)
        else
            cell:setImageColor(GuiOverlay.STATE_NORMAL, 1, 1, 1)
        end
    end

    local iconCell = cell:getAttribute("icon")
    if iconCell ~= nil then
        if row.icon ~= nil then
            iconCell:setImageFilename(row.icon)
            iconCell:setVisible(true)
        else
            iconCell:setVisible(false)
        end
    end

    -- Name split: baseName empty -> show idNoName only; else show id + name.
    local idNoNameCell = cell:getAttribute("idNoName")
    local idCell       = cell:getAttribute("id")
    local nameCell     = cell:getAttribute("name")
    local hasBaseName  = row.baseName ~= ""
    if idNoNameCell ~= nil then
        idNoNameCell:setText(row.displayIdentifier)
        idNoNameCell:setVisible(not hasBaseName)
    end
    if idCell ~= nil then
        idCell:setText(row.identifier)
        idCell:setVisible(hasBaseName)
    end
    if nameCell ~= nil then
        nameCell:setText(row.displayName)
        nameCell:setVisible(hasBaseName)
    end

    local priceCell = cell:getAttribute("price")
    if priceCell ~= nil then
        if priceCell.setValue ~= nil then
            priceCell:setValue(row.price)
        else
            priceCell:setText(tostring(row.price))
        end
    end

    local descriptor = cell:getAttribute("herdsmanPurchase")
    if descriptor ~= nil then
        descriptor:setVisible(row.descriptorVisible)
        if row.descriptorVisible then
            descriptor:setText(row.descriptorText)
        end
    end
end

-- =============================================================================
-- Detail pane
-- =============================================================================

--- Apply a value/ratio + invertedBar/disabled to a single status bar element,
--- mirroring base-game InGameMenuAnimalsFrame:setStatusBarValue.
--- @param statusBarElement table|nil
--- @param value number|nil ratio in [0..1]
--- @param invertedBar boolean|nil
--- @param disabled boolean|nil
function RLMenuInfoFrame:setStatusBarValue(statusBarElement, value, invertedBar, disabled)
    if statusBarElement == nil then return end
    -- Clamp so a malformed ratio cannot compute a negative width.
    value = math.max(0, math.min(1, value or 0))
    -- Color logic intentionally skipped: the fs25_animalSmallStatusBar
    -- profile default is green, and base-game's setStatusBarValue color
    -- branches produce counterintuitive results (full water trough renders
    -- red). Until we work out the actual color rules, leave bars green and
    -- communicate state through bar width only.

    if statusBarElement.parent ~= nil and statusBarElement.parent.size ~= nil then
        local fullWidth = statusBarElement.parent.size[1] - (statusBarElement.margin and statusBarElement.margin[1] * 2 or 0)
        local minSize = 0
        if statusBarElement.startSize ~= nil then
            minSize = statusBarElement.startSize[1] + statusBarElement.endSize[1]
        end
        statusBarElement:setSize(math.max(minSize, fullWidth * math.min(1, value)), nil)
    end

    -- Always coalesce + call setDisabled, never skip on nil. Status bar
    -- elements are reused across husbandry switches (5 fixed condition
    -- slots, 5 fixed food slots), so a stale disabled=true from a
    -- previous husbandry would leak forward and render the bar grey on
    -- the next husbandry where the row should be enabled. Mirrors base-
    -- game setStatusBarValue pattern.
    if statusBarElement.setDisabled ~= nil then
        statusBarElement:setDisabled(disabled or false)
    end
end

--- Refresh the money box from the current farm balance. Hides the box when
--- the farm is missing or no farm context is available.
function RLMenuInfoFrame:updateMoneyDisplay()
    if self.moneyBox == nil and self.balanceText == nil then return end

    local balance
    if self.farmId ~= nil then
        balance = RLAnimalInfoService.getFarmBalance(self.farmId)
    end

    Log:debug("RLMenuInfoFrame:updateMoneyDisplay: farmId=%s balance=%s",
        tostring(self.farmId), tostring(balance))

    local visible = balance ~= nil
    if self.moneyBox ~= nil and self.moneyBox.setVisible ~= nil then
        self.moneyBox:setVisible(visible)
    end
    if self.moneyBoxBg ~= nil and self.moneyBoxBg.setVisible ~= nil then
        self.moneyBoxBg:setVisible(visible)
    end

    if not visible then return end

    if self.balanceText ~= nil then
        self.balanceText:setText(g_i18n:formatMoney(balance, 0, true, false))
        if balance < 0 and ShopMenu ~= nil and ShopMenu.GUI_PROFILE ~= nil then
            self.balanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY_NEGATIVE, nil, true)
        elseif ShopMenu ~= nil and ShopMenu.GUI_PROFILE ~= nil then
            self.balanceText:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY, nil, true)
        end
    end

    if self.moneyBox ~= nil and self.moneyBox.invalidateLayout ~= nil then
        self.moneyBox:invalidateLayout()
    end
end

--- Refresh the pen column from the currently selected husbandry. Hides
--- the pen box when no husbandry is selected.
function RLMenuInfoFrame:updatePenDisplay()
    if self.penBox == nil then return end

    local display
    if self.selectedHusbandry ~= nil then
        display = RLAnimalInfoService.getHusbandryDisplay(self.selectedHusbandry, self.farmId)
    end

    if display == nil then
        self.penBox:setVisible(false)
        Log:trace("RLMenuInfoFrame:updatePenDisplay: no husbandry, pen hidden")
        return
    end

    Log:debug("RLMenuInfoFrame:updatePenDisplay: husbandry='%s' count=%s",
        display.name, display.countText)
    self.penBox:setVisible(true)

    if self.penNameText ~= nil then self.penNameText:setText(display.name) end
    if self.penCountText ~= nil then self.penCountText:setText(display.countText) end
    if self.penIcon ~= nil then
        if display.penImageFilename ~= nil then
            self.penIcon:setImageFilename(display.penImageFilename)
            self.penIcon:setVisible(true)
        else
            self.penIcon:setVisible(false)
        end
    end

    -- Conditions: show up to NUM_CONDITION_ROWS, hide unused
    if self.conditionRow ~= nil then
        for index = 1, RLMenuInfoFrame.NUM_CONDITION_ROWS do
            local row = self.conditionRow[index]
            local info = display.conditionInfos[index]
            if row ~= nil then row:setVisible(info ~= nil) end
            if info ~= nil and row ~= nil then
                local valueText = info.valueText
                if valueText == nil then
                    valueText = g_i18n:formatVolume(info.value or 0, 0, info.customUnitText)
                end
                if self.conditionLabel and self.conditionLabel[index] then
                    self.conditionLabel[index]:setText(info.title or "")
                end
                if self.conditionValue and self.conditionValue[index] then
                    self.conditionValue[index]:setText(valueText)
                end
                if self.conditionStatusBar and self.conditionStatusBar[index] then
                    self:setStatusBarValue(self.conditionStatusBar[index], info.ratio, info.invertedBar, info.disabled)
                end
            end
        end
    end

    -- Food rows: each food row + the foodRowTotal summary at the top
    if self.foodRow ~= nil then
        for index = 1, RLMenuInfoFrame.NUM_FOOD_ROWS do
            local row = self.foodRow[index]
            local info = display.foodInfos[index]
            if row ~= nil then row:setVisible(info ~= nil) end
            if info ~= nil and row ~= nil then
                local valueText = g_i18n:formatVolume(info.value or 0, 0)
                if self.foodLabel and self.foodLabel[index] then
                    self.foodLabel[index]:setText(info.title or "")
                end
                if self.foodValue and self.foodValue[index] then
                    self.foodValue[index]:setText(valueText)
                end
                if self.foodStatusBar and self.foodStatusBar[index] then
                    self:setStatusBarValue(self.foodStatusBar[index], info.ratio, info.invertedBar, info.disabled)
                end
            end
        end
    end

    -- Hide the entire food chrome (header, total row) when this husbandry
    -- has no food mixes (e.g. chicken coops). Otherwise the user sees a
    -- dangling "Total: 0 l" green bar.
    local hasFood = #display.foodInfos > 0
    if self.foodRowTotal ~= nil then self.foodRowTotal:setVisible(hasFood) end
    if self.penFoodHeader ~= nil then self.penFoodHeader:setVisible(hasFood) end

    if hasFood then
        if self.foodRowTotalValue ~= nil then
            self.foodRowTotalValue:setText(g_i18n:formatVolume(display.foodTotalValue, 0))
        end
        if self.foodRowTotalStatusBar ~= nil then
            self:setStatusBarValue(self.foodRowTotalStatusBar, display.foodTotalRatio, false)
        end
        if self.foodHeader ~= nil then
            self.foodHeader:setText(string.format("%s (%s)",
                g_i18n:getText("ui_silos_totalCapacity"),
                g_i18n:getText("animals_foodMixEffectiveness")))
        end
    end

    if self.penRequirementsLayout ~= nil and self.penRequirementsLayout.invalidateLayout ~= nil then
        self.penRequirementsLayout:invalidateLayout()
    end
end

--- Render the per-animal stat rows from husbandry:getAnimalInfos as a
--- 2x5 grid of plain label/value text pairs (NO status bars - that's the
--- conditions/food idiom). Variable count handled by hide-unused.
--- @param statRows table list of {title, valueText, ...} from getAnimalInfos
function RLMenuInfoFrame:updateAnimalStats(statRows)
    if self.statRow == nil then return end
    for index = 1, RLMenuInfoFrame.NUM_STAT_ROWS do
        local row = self.statRow[index]
        local info = statRows[index]
        if row ~= nil then row:setVisible(info ~= nil) end
        if info ~= nil then
            local valueText = info.valueText
            if valueText == nil and info.value ~= nil then
                valueText = g_i18n:formatVolume(info.value, 0, info.customUnitText)
            end
            if self.statLabel and self.statLabel[index] then
                self.statLabel[index]:setText(info.title or "")
            end
            if self.statValue and self.statValue[index] then
                self.statValue[index]:setText(valueText or "")
            end
        end
    end
end

--- Refresh the animal column from a cluster/animal. Hides the animal box
--- when no animal is supplied.
--- @param animal table|nil
function RLMenuInfoFrame:updateAnimalDisplay(animal)
    if self.animalBox == nil then return end

    local display
    if animal ~= nil then
        display = RLAnimalInfoService.getAnimalDisplay(animal, self.selectedHusbandry)
    end

    if display == nil then
        self.animalBox:setVisible(false)
        Log:trace("RLMenuInfoFrame:updateAnimalDisplay: no animal, animal box hidden")
        return
    end

    Log:debug("RLMenuInfoFrame:updateAnimalDisplay: farmId=%s uniqueId=%s",
        tostring(animal.farmId), tostring(animal.uniqueId))
    self.animalBox:setVisible(true)

    if self.animalDetailTypeNameText ~= nil then
        self.animalDetailTypeNameText:setText(display.typeName)
    end
    if self.animalDetailTypeImage ~= nil then
        if display.animalImageFilename ~= nil then
            self.animalDetailTypeImage:setImageFilename(display.animalImageFilename)
            self.animalDetailTypeImage:setVisible(true)
        else
            self.animalDetailTypeImage:setVisible(false)
        end
    end

    -- Stat rows from husbandry:getAnimalInfos. Variable count (3 rows for
    -- a pig, 8+ for a monitored pregnant cow). Hide unused slots.
    self:updateAnimalStats(display.statRows or {})

    if self.animalDescriptionText ~= nil then
        self.animalDescriptionText:setText(display.description or "")
    end

    -- Pedigree
    self:_renderPedigreeRow(self.pedigreeMotherText, display.pedigreeMother)
    self:_renderPedigreeRow(self.pedigreeFatherText, display.pedigreeFather)
    if self.pedigreeChildrenText ~= nil and display.pedigreeChildren ~= nil then
        self.pedigreeChildrenText:setText(string.format("%s: %d",
            g_i18n:getText(display.pedigreeChildren.labelKey), display.pedigreeChildren.count))
    end

    -- Genetics rows
    if self.geneticsRow ~= nil then
        for index = 1, RLMenuInfoFrame.NUM_GENETICS_ROWS do
            local row = self.geneticsRow[index]
            local data = display.geneticsRows[index]
            if row ~= nil then row:setVisible(data ~= nil) end
            if data ~= nil and row ~= nil then
                if self.geneticsLabel and self.geneticsLabel[index] then
                    self.geneticsLabel[index]:setText(g_i18n:getText(data.labelKey))
                end
                if self.geneticsValue and self.geneticsValue[index] then
                    self.geneticsValue[index]:setText(g_i18n:getText(data.valueKey))
                end
                -- Always reset color so the previous selection's tier color
                -- can't bleed onto a new row. Unknown colorKey -> neutral white.
                local color = RLMenuInfoFrame.GENETICS_COLOR[data.colorKey]
                    or RLMenuInfoFrame.GENETICS_COLOR_NEUTRAL
                if self.geneticsLabel and self.geneticsLabel[index] and self.geneticsLabel[index].setTextColor then
                    self.geneticsLabel[index]:setTextColor(unpack(color))
                end
                if self.geneticsValue and self.geneticsValue[index] and self.geneticsValue[index].setTextColor then
                    self.geneticsValue[index]:setTextColor(unpack(color))
                end
            end
        end
    end

    -- Disease rows (read-only, no Treat button). Hide the entire diseaseColumn
    -- BoxLayout when the animal has no diseases so the section header doesn't
    -- linger above an empty area.
    local hasDiseases = #display.diseaseRows > 0
    if self.diseaseColumn ~= nil then
        self.diseaseColumn:setVisible(hasDiseases)
    end
    if hasDiseases and self.diseaseRow ~= nil then
        for index = 1, RLMenuInfoFrame.NUM_DISEASE_ROWS do
            local row = self.diseaseRow[index]
            local data = display.diseaseRows[index]
            if row ~= nil then row:setVisible(data ~= nil) end
            if data ~= nil and row ~= nil then
                if self.diseaseName and self.diseaseName[index] then
                    self.diseaseName[index]:setText(data.name or "")
                end
                if self.diseaseStatus and self.diseaseStatus[index] then
                    self.diseaseStatus[index]:setText(data.status or "")
                end
            end
        end
    end

    -- Monitor input/output rows. Hide the entire monitorColumnsRow when
    -- the animal is not monitored.
    local hasMonitor = display.hasMonitor or false
    if self.monitorColumnsRow ~= nil then
        self.monitorColumnsRow:setVisible(hasMonitor)
    end
    if hasMonitor then
        if self.inputRow ~= nil then
            for index = 1, RLMenuInfoFrame.NUM_INPUT_ROWS do
                local row = self.inputRow[index]
                local data = display.inputRows[index]
                if row ~= nil then row:setVisible(data ~= nil) end
                if data ~= nil and row ~= nil then
                    if self.inputLabel and self.inputLabel[index] then
                        self.inputLabel[index]:setText(data.title or "")
                    end
                    if self.inputValue and self.inputValue[index] then
                        self.inputValue[index]:setText(data.valueText or "")
                    end
                end
            end
        end
        if self.outputRow ~= nil then
            for index = 1, RLMenuInfoFrame.NUM_OUTPUT_ROWS do
                local row = self.outputRow[index]
                local data = display.outputRows[index]
                if row ~= nil then row:setVisible(data ~= nil) end
                if data ~= nil and row ~= nil then
                    if self.outputLabel and self.outputLabel[index] then
                        self.outputLabel[index]:setText(data.title or "")
                    end
                    if self.outputValue and self.outputValue[index] then
                        self.outputValue[index]:setText(data.valueText or "")
                    end
                end
            end
        end
        if self.inputColumn ~= nil and self.inputColumn.invalidateLayout ~= nil then
            self.inputColumn:invalidateLayout()
        end
        if self.outputColumn ~= nil and self.outputColumn.invalidateLayout ~= nil then
            self.outputColumn:invalidateLayout()
        end
    end

    -- Invalidate every BoxLayout in the scrollable area so genetics,
    -- pedigree, the horizontal columns wrapper, and the outer
    -- ScrollingLayout all recompute their stack heights and total content
    -- size when row visibility changes (5 vs 6 genetics rows by species,
    -- variable stat row count, disease section show/hide, etc.).
    if self.pedigreeColumn ~= nil and self.pedigreeColumn.invalidateLayout ~= nil then
        self.pedigreeColumn:invalidateLayout()
    end
    if self.geneticsColumn ~= nil and self.geneticsColumn.invalidateLayout ~= nil then
        self.geneticsColumn:invalidateLayout()
    end
    if hasDiseases and self.diseaseColumn ~= nil and self.diseaseColumn.invalidateLayout ~= nil then
        self.diseaseColumn:invalidateLayout()
    end
    if self.animalColumnsRow ~= nil and self.animalColumnsRow.invalidateLayout ~= nil then
        self.animalColumnsRow:invalidateLayout()
    end
    if hasMonitor and self.monitorColumnsRow ~= nil and self.monitorColumnsRow.invalidateLayout ~= nil then
        self.monitorColumnsRow:invalidateLayout()
    end
    if self.animalScrollLayout ~= nil and self.animalScrollLayout.invalidateLayout ~= nil then
        self.animalScrollLayout:invalidateLayout()
    end
end

--- Render one parent pedigree row (mother or father). Hides the id and
--- substitutes "(unknown)" when motherId/fatherId is nil or "-1".
--- @param textElement table|nil
--- @param row table {labelKey, idText|nil, unknownKey|nil}
function RLMenuInfoFrame:_renderPedigreeRow(textElement, row)
    if textElement == nil or row == nil then return end
    local label = g_i18n:getText(row.labelKey)
    local valueText
    if row.idText ~= nil then
        valueText = string.format("%s (%s)", label, row.idText)
    else
        valueText = string.format("%s (%s)", label, g_i18n:getText(row.unknownKey or "rl_ui_unknown"))
    end
    textElement:setText(valueText)
end

--- Hide the pen and animal boxes (header + money stay visible). Used on
--- onFrameOpen and when no husbandry is selected.
function RLMenuInfoFrame:clearDetail()
    Log:trace("RLMenuInfoFrame:clearDetail")
    if self.penBox ~= nil then self.penBox:setVisible(false) end
    self:clearAnimalDetail()
end

--- Hide just the animal box. Used on husbandry change before a row is picked.
function RLMenuInfoFrame:clearAnimalDetail()
    Log:trace("RLMenuInfoFrame:clearAnimalDetail")
    if self.animalBox ~= nil then self.animalBox:setVisible(false) end
end

-- =============================================================================
-- Mutation handlers
-- =============================================================================

---Toggle player mark. Local-only (RLRM-145 tracks MP fix).
function RLMenuInfoFrame:onClickMark()
    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onClickMark: no animal selected, early return")
        return
    end

    local wasMarked = animal.getMarked ~= nil and animal:getMarked()
    local isMarked = not wasMarked
    Log:trace("RLMenuInfoFrame:onClickMark: farmId=%s uniqueId=%s wasMarked=%s -> isMarked=%s",
        tostring(animal.farmId), tostring(animal.uniqueId), tostring(wasMarked), tostring(isMarked))

    if isMarked then
        Log:trace("  branch: setMarked('PLAYER', true)")
        animal:setMarked("PLAYER", true)
    else
        -- Clears ALL marks including AI Manager (RLRM-146 tracks fix)
        Log:trace("  branch: setMarked(nil, false)")
        animal:setMarked(nil, false)
    end

    Log:debug("RLMenuInfoFrame:onClickMark: farmId=%s uniqueId=%s marked=%s",
        tostring(animal.farmId), tostring(animal.uniqueId), tostring(isMarked))
    self:refreshAfterMutation()
end

---Toggle monitor. Delegates to RLAnimalInfoService.
function RLMenuInfoFrame:onClickMonitor()
    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onClickMonitor: no animal selected, early return")
        return
    end

    Log:trace("RLMenuInfoFrame:onClickMonitor: farmId=%s uniqueId=%s monitor.active=%s monitor.removed=%s",
        tostring(animal.farmId), tostring(animal.uniqueId),
        tostring(animal.monitor and animal.monitor.active), tostring(animal.monitor and animal.monitor.removed))

    local active, removed = RLAnimalInfoService.toggleMonitor(animal)

    Log:debug("RLMenuInfoFrame:onClickMonitor: farmId=%s uniqueId=%s -> active=%s removed=%s",
        tostring(animal.farmId), tostring(animal.uniqueId), tostring(active), tostring(removed))
    self:refreshAfterMutation()
end

---Open rename dialog. Pre-fills with current name or a random one.
function RLMenuInfoFrame:onClickRename()
    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onClickRename: no animal selected, early return")
        return
    end

    local name = animal.name
    if name == nil and g_currentMission ~= nil
        and g_currentMission.animalNameSystem ~= nil then
        name = g_currentMission.animalNameSystem:getRandomName(animal.gender)
        Log:trace("RLMenuInfoFrame:onClickRename: no existing name, generated random: %s", tostring(name))
    else
        Log:trace("RLMenuInfoFrame:onClickRename: existing name: %s", tostring(name))
    end

    Log:debug("RLMenuInfoFrame:onClickRename: farmId=%s uniqueId=%s opening dialog, prefill=%s",
        tostring(animal.farmId), tostring(animal.uniqueId), tostring(name))
    NameInputDialog.show(self.onRenameDone, self, name, nil, 30, nil, animal.gender)
end

---NameInputDialog callback. Delegates to RLAnimalInfoService.
---@param text string
---@param clickOk boolean
function RLMenuInfoFrame:onRenameDone(text, clickOk)
    if not clickOk then
        Log:trace("RLMenuInfoFrame:onRenameDone: user cancelled dialog")
        return
    end

    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onRenameDone: no animal selected, early return")
        return
    end

    Log:debug("RLMenuInfoFrame:onRenameDone: farmId=%s uniqueId=%s newName=%s",
        tostring(animal.farmId), tostring(animal.uniqueId), tostring(text))
    RLAnimalInfoService.renameAnimal(animal, text)
    self:refreshAfterMutation()
end

---Open disease treatment dialog.
function RLMenuInfoFrame:onClickDiseases()
    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onClickDiseases: no animal selected, early return")
        return
    end
    if DiseaseDialog == nil or DiseaseDialog.show == nil then
        Log:warning("RLMenuInfoFrame:onClickDiseases: DiseaseDialog unavailable")
        return
    end

    Log:debug("RLMenuInfoFrame:onClickDiseases: farmId=%s uniqueId=%s opening dialog",
        tostring(animal.farmId), tostring(animal.uniqueId))
    DiseaseDialog.show(animal)
end

---Open insemination dialog.
function RLMenuInfoFrame:onClickInseminate()
    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onClickInseminate: no animal selected, early return")
        return
    end
    if g_localPlayer == nil then
        Log:trace("RLMenuInfoFrame:onClickInseminate: g_localPlayer nil, early return")
        return
    end

    Log:debug("RLMenuInfoFrame:onClickInseminate: farmId=%s uniqueId=%s typeIndex=%s opening dialog",
        tostring(animal.farmId), tostring(animal.uniqueId), tostring(animal.animalTypeIndex))
    AnimalAIDialog.show(self.selectedHusbandry, g_localPlayer.farmId,
        animal.animalTypeIndex, animal)
end

---Castrate the selected animal. Local-only (RLRM-145 tracks MP fix).
function RLMenuInfoFrame:onClickCastrate()
    local animal = self:getSelectedAnimal()
    if animal == nil then
        Log:trace("RLMenuInfoFrame:onClickCastrate: no animal selected, early return")
        return
    end

    Log:trace("RLMenuInfoFrame:onClickCastrate: farmId=%s uniqueId=%s isCastrated=%s fertility=%.2f",
        tostring(animal.farmId), tostring(animal.uniqueId),
        tostring(animal.isCastrated), animal.genetics and animal.genetics.fertility or -1)

    animal.isCastrated = true
    animal.genetics.fertility = 0

    Log:debug("RLMenuInfoFrame:onClickCastrate: farmId=%s uniqueId=%s castrated, fertility=0",
        tostring(animal.farmId), tostring(animal.uniqueId))
    self:refreshAfterMutation()
end
