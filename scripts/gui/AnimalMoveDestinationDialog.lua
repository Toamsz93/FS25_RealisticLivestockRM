local Log = RmLogging.getLogger("RLRM")

AnimalMoveDestinationDialog = {}

local AnimalMoveDestinationDialog_mt = Class(AnimalMoveDestinationDialog, MessageDialog)
local modDirectory = g_currentModDirectory


function AnimalMoveDestinationDialog.register()
    local dialog = AnimalMoveDestinationDialog.new()
    g_gui:loadGui(modDirectory .. "gui/AnimalMoveDestinationDialog.xml", "AnimalMoveDestinationDialog", dialog)
    AnimalMoveDestinationDialog.INSTANCE = dialog
    Log:trace("AnimalMoveDestinationDialog.register: dialog registered")
end


function AnimalMoveDestinationDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or AnimalMoveDestinationDialog_mt)

    self.entries = {}
    self.selectedIndex = nil
    self.callback = nil
    self.callbackTarget = nil

    return self
end


function AnimalMoveDestinationDialog:onGuiSetupFinished()
    AnimalMoveDestinationDialog:superClass().onGuiSetupFinished(self)

    self.destinationList = self:getDescendantById("destinationList")
    self.emptyListText = self:getDescendantById("emptyListText")
    self.confirmButton = self:getDescendantById("confirmButton")

    self.destinationList:setDataSource(self)

    Log:trace("AnimalMoveDestinationDialog:onGuiSetupFinished: elements resolved")
end


--- Show the dialog with destination entries
---@param callback function Called with selected entry or nil on cancel
---@param target table Callback target
---@param entries table Array of destination entries from getValidDestinations
function AnimalMoveDestinationDialog.show(callback, target, entries)
    if AnimalMoveDestinationDialog.INSTANCE == nil then
        AnimalMoveDestinationDialog.register()
    end

    local dialog = AnimalMoveDestinationDialog.INSTANCE
    dialog.entries = entries or {}
    dialog.callback = callback
    dialog.callbackTarget = target
    dialog.selectedIndex = nil

    Log:trace("AnimalMoveDestinationDialog.show: %d entries", #dialog.entries)
    g_gui:showDialog("AnimalMoveDestinationDialog")
end


function AnimalMoveDestinationDialog:onOpen()
    AnimalMoveDestinationDialog:superClass().onOpen(self)

    local hasEntries = #self.entries > 0

    self.destinationList:setVisible(hasEntries)
    self.emptyListText:setVisible(not hasEntries)
    self.confirmButton:setDisabled(true)

    if hasEntries then
        self.destinationList:reloadData()
        self.selectedIndex = 1
        self.confirmButton:setDisabled(false)
    end

    Log:trace("AnimalMoveDestinationDialog:onOpen: hasEntries=%s", tostring(hasEntries))
end


function AnimalMoveDestinationDialog:getNumberOfSections()
    return 1
end


function AnimalMoveDestinationDialog:getNumberOfItemsInSection(list, section)
    return #self.entries
end


function AnimalMoveDestinationDialog:getTitleForSectionHeader(list, section)
    return ""
end


-- SmoothList DataSource: populate cell
function AnimalMoveDestinationDialog:populateCellForItemInSection(list, section, index, cell)
    local entry = self.entries[index]
    if entry == nil then return end

    local nameElement = cell:getAttribute("destinationName")
    local capacityElement = cell:getAttribute("capacityText")
    local constraintElement = cell:getAttribute("constraintText")

    nameElement:setText(entry.name)
    capacityElement:setText(string.format("%d/%d", entry.currentCount, entry.maxCount))

    if entry.isEPP and entry.minAge ~= nil and entry.maxAge ~= nil then
        constraintElement:setText(string.format(g_i18n:getText("rl_ui_moveEPPAgeFormat"), entry.minAge, entry.maxAge))
        constraintElement:setVisible(true)
    else
        constraintElement:setVisible(false)
    end

    Log:trace("AnimalMoveDestinationDialog:populateCell: index=%d name='%s' %d/%d isEPP=%s",
        index, entry.name, entry.currentCount, entry.maxCount, tostring(entry.isEPP))
end


function AnimalMoveDestinationDialog:onListClick(list, section, index, cell)
    self.selectedIndex = index
    self.confirmButton:setDisabled(false)
    Log:trace("AnimalMoveDestinationDialog:onListClick: selected index=%d", index)
end


function AnimalMoveDestinationDialog:onClickConfirm()
    -- Read selection from the SmoothList (tracks keyboard/gamepad nav), not our onClick-only field
    local selectedIndex = self.destinationList:getSelectedIndexInSection()
    Log:trace("AnimalMoveDestinationDialog:onClickConfirm: selectedIndex=%s (list=%s)",
        tostring(self.selectedIndex), tostring(selectedIndex))

    local entry = nil
    if selectedIndex ~= nil and selectedIndex > 0 then
        entry = self.entries[selectedIndex]
    end

    self:close()

    if self.callback ~= nil then
        if self.callbackTarget ~= nil then
            self.callback(self.callbackTarget, entry)
        else
            self.callback(entry)
        end
    end
end


function AnimalMoveDestinationDialog:onClickCancel()
    Log:trace("AnimalMoveDestinationDialog:onClickCancel")

    self:close()

    if self.callback ~= nil then
        if self.callbackTarget ~= nil then
            self.callback(self.callbackTarget, nil)
        else
            self.callback(nil)
        end
    end
end
