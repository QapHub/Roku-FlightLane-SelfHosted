sub init()
    m.config = GetAppConfig()
    m.addressLabel = m.top.FindNode("addressLabel")
    m.settingsList = m.top.FindNode("settingsList")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.pendingSettings = invalid
    m.localToken = ""
    m.addressDialog = invalid
    m.geocodeRequestInFlight = false
    m.registrationRequestInFlight = false
    m.settingsList.ObserveField("itemSelected", "OnSettingsItemSelected")
    m.top.SetFocus(true)
    LoadLocalSession()
end sub

sub LoadLocalSession()
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "loadAuth"
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub LoadSettings()
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "load"
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub StartDeviceRegistration()
    if m.registrationRequestInFlight
        return
    end if
    m.registrationRequestInFlight = true
    m.statusLabel.text = "CONNECTING THIS ROKU TO FLIGHT LANE..."
    m.statusLabel.color = "0x7DD3FCFF"
    m.registrationTask = CreateObject("roSGNode", "FlightApiTask")
    m.registrationTask.operation = "register"
    m.registrationTask.params = {}
    m.registrationTask.ObserveField("result", "OnRegistrationResult")
    m.registrationTask.control = "run"
end sub

sub SaveLocalSession(auth as object)
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "saveAuth"
    m.settingsTask.settings = auth
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub OnRegistrationResult(event as object)
    result = event.GetData()
    m.registrationRequestInFlight = false
    m.registrationTask = invalid
    if result = invalid or result.ok <> true
        errorMessage = "Flight Lane could not connect this Roku."
        if result <> invalid
            errorMessage = StringOr(result.errorMessage, errorMessage)
        end if
        m.statusLabel.text = errorMessage + " Press OK to retry."
        m.statusLabel.color = "0xFCA5A5FF"
        return
    end if
    m.statusLabel.text = "SAVING SECURE CONNECTION..."
    SaveLocalSession(result.data)
end sub

sub SaveSettings()
    m.statusLabel.text = "SAVING..."
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "save"
    m.settingsTask.settings = m.pendingSettings
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub OnSettingsResult(event as object)
    result = event.GetData()
    m.settingsTask = invalid
    if result = invalid
        return
    end if
    if result.operation = "loadAuth"
        if result.ok = true and result.configured = true
            m.localToken = StringOr(result.auth.token, "")
            LoadSettings()
        else
            StartDeviceRegistration()
        end if
        return
    else if result.operation = "saveAuth"
        if result.ok = true
            m.localToken = StringOr(result.auth.token, "")
            LoadSettings()
        else
            m.statusLabel.text = StringOr(result.errorMessage, "Unable to save the Flight Lane connection.") + " Press OK to retry."
            m.statusLabel.color = "0xFCA5A5FF"
        end if
        return
    end if
    if result.ok <> true
        m.statusLabel.text = StringOr(result.errorMessage, "Unable to save settings.")
        m.statusLabel.color = "0xFCA5A5FF"
        return
    end if

    if result.operation = "save"
        m.top.finished = true
        return
    end if

    if result.configured = true
        saved = result.settings
        m.pendingSettings = {
            address: StringOr(saved.address, "Saved home location")
            latitude: NumberOr(saved.latitude, 0)
            longitude: NumberOr(saved.longitude, 0)
            radiusMiles: ClampSettingsRadius(NumberOr(saved.radiusMiles, 4))
            idleMinutes: 0
            showFlyoverCount: saved.showFlyoverCount
            trailMinutes: saved.trailMinutes
            pollSeconds: saved.pollSeconds
            colorByAltitude: saved.colorByAltitude
        }
        BuildContent()
        m.settingsList.SetFocus(true)
    else
        m.pendingSettings = {
            address: "No address configured"
            latitude: 0
            longitude: 0
            radiusMiles: ClampSettingsRadius(m.config.radiusMiles)
            idleMinutes: 0
        }
        BuildContent()
        ShowAddressDialog()
    end if
end sub

sub BuildContent()
    m.addressLabel.text = m.pendingSettings.address
    rows = [
        "Change home address"
        "Detection radius: " + Int(m.pendingSettings.radiusMiles).ToStr() + " miles"
        "Save and exit"
    ]
    content = CreateObject("roSGNode", "ContentNode")
    for each rowTitle in rows
        item = content.CreateChild("ContentNode")
        item.title = rowTitle
    end for
    m.settingsList.content = content
end sub

sub OnSettingsItemSelected(event as object)
    index = event.GetData()
    if index = 0
        ShowAddressDialog()
    else if index = 1
        AdjustRadius(1)
    else if index = 2
        if m.pendingSettings.latitude = 0 and m.pendingSettings.longitude = 0
            m.statusLabel.text = "Enter a home address before saving."
            m.statusLabel.color = "0xFCA5A5FF"
        else
            SaveSettings()
        end if
    end if
end sub

sub ShowAddressDialog()
    if m.addressDialog <> invalid or m.geocodeRequestInFlight
        return
    end if
    if m.localToken = ""
        StartDeviceRegistration()
        return
    end if
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Enter your home address"
    dialog.message = ["Include street, city, state, and ZIP code."]
    dialog.buttons = ["Use this address", "Cancel"]
    dialog.keyboardDomain = "alphanumeric"
    if m.pendingSettings.address <> "No address configured"
        dialog.text = m.pendingSettings.address
    end if
    dialog.ObserveField("buttonSelected", "OnAddressDialogButton")
    m.addressDialog = dialog
    m.top.dialog = dialog
end sub

sub OnAddressDialogButton(event as object)
    if m.addressDialog = invalid
        return
    end if
    buttonIndex = event.GetData()
    address = m.addressDialog.text
    m.addressDialog.close = true
    m.addressDialog = invalid
    if buttonIndex = 0 and address.Trim() <> ""
        m.geocodeRequestInFlight = true
        m.statusLabel.text = "FINDING HOME LOCATION..."
        m.statusLabel.color = "0x7DD3FCFF"
        m.geocodeTask = CreateObject("roSGNode", "FlightApiTask")
        m.geocodeTask.operation = "geocode"
        m.geocodeTask.params = { address: address, localToken: m.localToken }
        m.geocodeTask.ObserveField("result", "OnGeocodeResult")
        m.geocodeTask.control = "run"
    else
        m.settingsList.SetFocus(true)
    end if
end sub

sub OnGeocodeResult(event as object)
    result = event.GetData()
    m.geocodeRequestInFlight = false
    m.geocodeTask = invalid
    if result = invalid
        return
    end if
    if result.ok <> true
        m.statusLabel.text = StringOr(result.errorMessage, "Address was not found.")
        m.statusLabel.color = "0xFCA5A5FF"
        m.settingsList.SetFocus(true)
        return
    end if
    m.pendingSettings.address = result.data.address
    m.pendingSettings.latitude = result.data.latitude
    m.pendingSettings.longitude = result.data.longitude
    m.statusLabel.text = "LOCATION FOUND - CHOOSE SAVE AND EXIT"
    m.statusLabel.color = "0x86EFACFF"
    BuildContent()
    m.settingsList.SetFocus(true)
end sub

sub AdjustRadius(direction as integer)
    m.pendingSettings.radiusMiles = StepRadius(m.pendingSettings.radiusMiles, direction, true)
    BuildContent()
    m.settingsList.jumpToItem = 1
end sub

function ClampSettingsRadius(value as float) as float
    if value < 1
        return 1
    end if
    if value > MaxRadiusMiles()
        return MaxRadiusMiles()
    end if
    return Int(value)
end function

function onKeyEvent(key as string, press as boolean) as boolean
    if not press or m.addressDialog <> invalid
        return false
    end if
    if key = "back"
        m.top.finished = true
        return true
    end if
    if key = "OK" and m.localToken = "" and not m.registrationRequestInFlight
        StartDeviceRegistration()
        return true
    end if
    if key = "left" and m.settingsList.itemFocused = 1
        AdjustRadius(-1)
        return true
    end if
    if key = "right" and m.settingsList.itemFocused = 1
        AdjustRadius(1)
        return true
    end if
    return false
end function
