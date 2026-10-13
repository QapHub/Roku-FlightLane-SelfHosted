sub init()
    m.config = GetAppConfig()
    appInfo = CreateObject("roAppInfo")
    m.isScreensaver = appInfo.GetValue("screensaver_title") <> ""
    m.appTitle = m.top.FindNode("appTitle")
    m.subtitle = m.top.FindNode("subtitle")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.currentDateLabel = m.top.FindNode("currentDateLabel")
    m.currentTimeLabel = m.top.FindNode("currentTimeLabel")
    m.setupPanel = m.top.FindNode("setupPanel")
    m.setupMessage = m.top.FindNode("setupMessage")
    m.mainPanel = m.top.FindNode("mainPanel")
    m.settingsPanel = m.top.FindNode("settingsPanel")
    m.settingsAddressLabel = m.top.FindNode("settingsAddressLabel")
    m.settingsList = m.top.FindNode("settingsList")
    m.satelliteMap = m.top.FindNode("satelliteMap")
    m.overviewRadar = m.top.FindNode("overviewRadar")
    m.markerLayer = m.top.FindNode("markerLayer")
    m.closeupPip = m.top.FindNode("closeupPip")
    m.closeupPipTitle = m.top.FindNode("closeupPipTitle")
    m.closeupSatelliteMaps = [m.top.FindNode("closeupSatelliteMapA"), m.top.FindNode("closeupSatelliteMapB")]
    m.closeupImageryCredit = m.top.FindNode("closeupImageryCredit")
    m.closeupMapActiveIndex = 0
    m.closeupMapPendingIndex = -1
    m.closeupMapStates = [
        { url: "pkg:/images/map-backdrop.jpg", centerEastMiles: invalid, centerNorthMiles: invalid, baseOffset: 0 }
        { url: "pkg:/images/map-backdrop.jpg", centerEastMiles: invalid, centerNorthMiles: invalid, baseOffset: 0 }
    ]
    m.closeupMarkerLayer = m.top.FindNode("closeupMarkerLayer")
    m.rangeLabel = m.top.FindNode("rangeLabel")
    m.dataSourceLabel = m.top.FindNode("dataSourceLabel")
    m.spendNoticeLabel = m.top.FindNode("spendNoticeLabel")
    m.aircraftList = m.top.FindNode("aircraftList")
    m.emptyLabel = m.top.FindNode("emptyLabel")
    m.flyoverCountLabel = m.top.FindNode("flyoverCountLabel")
    m.selectedTitle = m.top.FindNode("selectedTitle")
    m.selectedMeta = m.top.FindNode("selectedMeta")
    m.airlineBadgeBackground = m.top.FindNode("airlineBadgeBackground")
    m.airlineCodeValue = m.top.FindNode("airlineCodeValue")
    m.airlineNameValue = m.top.FindNode("airlineNameValue")
    m.aircraftPhotoCard = m.top.FindNode("aircraftPhotoCard")
    m.aircraftPhoto = m.top.FindNode("aircraftPhoto")
    m.aircraftPhotoAttribution = m.top.FindNode("aircraftPhotoAttribution")
    m.altitudeValue = m.top.FindNode("altitudeValue")
    m.speedValue = m.top.FindNode("speedValue")
    m.distanceValue = m.top.FindNode("distanceValue")
    m.headingValue = m.top.FindNode("headingValue")
    m.phaseValue = m.top.FindNode("phaseValue")
    m.projectionValue = m.top.FindNode("projectionValue")
    m.routeValue = m.top.FindNode("routeValue")
    m.flightStatusValue = m.top.FindNode("flightStatusValue")
    m.departureValue = m.top.FindNode("departureValue")
    m.arrivalValue = m.top.FindNode("arrivalValue")
    m.footerControls = m.top.FindNode("footerControls")
    m.footerSettingsControls = m.top.FindNode("footerSettingsControls")
    m.footerLabel = m.top.FindNode("footerLabel")
    m.refreshTimer = m.top.FindNode("refreshTimer")
    m.motionTimer = m.top.FindNode("motionTimer")
    m.clockTimer = m.top.FindNode("clockTimer")
    m.detailCooldownTimer = m.top.FindNode("detailCooldownTimer")
    m.idleTimer = m.top.FindNode("idleTimer")
    m.satelliteRemoteRequested = false
    m.satelliteMap.ObserveField("loadStatus", "OnSatelliteLoadStatus")
    m.closeupSatelliteMaps[0].ObserveField("loadStatus", "OnCloseupSatelliteMapALoadStatus")
    m.closeupSatelliteMaps[1].ObserveField("loadStatus", "OnCloseupSatelliteMapBLoadStatus")
    m.aircraftPhoto.ObserveField("loadStatus", "OnAircraftPhotoLoadStatus")

    m.appTitle.text = m.config.appName
    m.subtitle.text = "LIVE AIRCRAFT WITHIN " + RoundTo(m.config.radiusMiles, 1).ToStr() + " MILES OF HOME"
    if false
        m.rangeLabel.text = "Satellite · " + RoundTo(m.config.radiusMiles, 1).ToStr() + " mi radius"
        m.satelliteRemoteRequested = true
        mapUrl = SatelliteMapUrl(m.config.homeLatitude, m.config.homeLongitude, m.config.mapZoom)
        m.satelliteMap.uri = mapUrl
    else
        m.rangeLabel.text = "Range · " + RoundTo(m.config.radiusMiles, 1).ToStr() + " mi"
    end if
    m.aircraft = []
    m.selectedIndex = 0
    m.nearbyRequestInFlight = false
    m.detailRequestInFlight = false
    m.detailCooldownActive = false
    m.detailCache = {}
    m.photoRequestInFlight = false
    m.photoCache = {}
    m.photoTask = invalid
    m.appMemoryPressure = false
    m.generalMemoryPressure = false
    m.lowMemoryMode = false
    m.radarMarkers = []
    m.interpolationSeconds = 0
    m.interpolationClock = CreateObject("roTimespan")
    m.interpolationClock.Mark()
    m.autoTrackClosest = true
    m.manualSelectedAircraftId = ""
    m.closeupMarkerRecord = invalid
    m.settings = invalid
    m.pendingSettings = invalid
    m.settingsOpen = false
    m.firstLaunchSetup = false
    m.registrationRequired = true
    m.localToken = ""
    m.localExpiresAt = ""
    m.registrationRequestInFlight = false
    m.addressDialog = invalid
    m.geocodeRequestInFlight = false
    m.displayMode = false
    m.locationRevision = 0
    m.flyoverRadiusMiles = 4.0
    m.flyoverWindowSeconds = 86400
    m.flyoverReentrySeconds = 900
    m.flyoverEvents = []
    m.flyoverLastSeen = {}
    m.flyoverHistoryLoaded = false
    m.flyoverSaveInFlight = false
    m.flyoverSaveQueued = false
    m.pendingFlyoverAircraft = invalid
    m.lastFlyoverPruneMinute = -1
    m.refreshTimer.duration = m.config.refreshSeconds
    m.motionTimer.duration = 0.2
    ShowFooterMessage("LOADING FLIGHT LANE…")

    m.aircraftList.ObserveField("itemFocused", "OnAircraftFocused")
    m.settingsList.ObserveField("itemSelected", "OnSettingsItemSelected")
    m.refreshTimer.ObserveField("fire", "OnRefreshTimer")
    m.motionTimer.ObserveField("fire", "OnMotionTimer")
    m.clockTimer.ObserveField("fire", "OnClockTimer")
    m.detailCooldownTimer.ObserveField("fire", "OnDetailCooldown")
    m.idleTimer.ObserveField("fire", "OnIdleTimer")

    m.mainPanel.visible = false
    m.setupPanel.visible = false
    m.settingsPanel.visible = false
    m.statusLabel.text = "LOADING SETTINGS..."
    UpdateCurrentClock()
    m.clockTimer.control = "start"
    m.top.SetFocus(true)
    LoadLocalSession()
    LoadFlyoverHistory()
end sub

sub OnMemoryUsagePercentChanged()
    m.appMemoryPressure = m.top.memoryUsagePercent >= 80
    UpdateMemoryPressureMode()
end sub

sub OnGeneralMemoryLevelChanged()
    generalLevel = LCase(m.top.generalMemoryLevel)
    m.generalMemoryPressure = generalLevel = "low" or generalLevel = "critical"
    UpdateMemoryPressureMode()
end sub

sub UpdateMemoryPressureMode()
    shouldReduceMemory = m.appMemoryPressure or m.generalMemoryPressure
    if shouldReduceMemory and not m.lowMemoryMode
        m.lowMemoryMode = true
        ReleaseOptionalVisualCaches()
    else if not shouldReduceMemory and m.lowMemoryMode
        m.lowMemoryMode = false
        if m.aircraft.Count() > 0
            UpdateSelection()
        end if
    end if
end sub

sub ReleaseOptionalVisualCaches()
    print "Flight Lane memory monitor: releasing optional photo, detail, and PIP map caches"
    m.detailCache = {}
    m.photoCache = {}
    HideAircraftPhoto()
    m.aircraftPhoto.uri = ""
    m.closeupPip.visible = false
    m.closeupMapPendingIndex = -1
    m.closeupMarkerRecord = invalid

    childCount = m.closeupMarkerLayer.GetChildCount()
    if childCount > 0
        m.closeupMarkerLayer.RemoveChildrenIndex(childCount, 0)
    end if
    for mapIndex = 0 to m.closeupSatelliteMaps.Count() - 1
        m.closeupSatelliteMaps[mapIndex].uri = ""
        m.closeupSatelliteMaps[mapIndex].visible = false
        m.closeupMapStates[mapIndex] = {
            url: ""
            centerEastMiles: invalid
            centerNorthMiles: invalid
            baseOffset: 0
        }
    end for
end sub

sub LoadFlyoverHistory()
    m.flyoverLoadTask = CreateObject("roSGNode", "FlyoverTask")
    m.flyoverLoadTask.operation = "load"
    m.flyoverLoadTask.ObserveField("result", "OnFlyoverTaskResult")
    m.flyoverLoadTask.control = "run"
end sub

sub SaveFlyoverHistory()
    if not m.flyoverHistoryLoaded
        return
    end if
    if m.flyoverSaveInFlight
        m.flyoverSaveQueued = true
        return
    end if

    m.flyoverSaveInFlight = true
    m.flyoverSaveQueued = false
    m.flyoverSaveTask = CreateObject("roSGNode", "FlyoverTask")
    m.flyoverSaveTask.operation = "save"
    m.flyoverSaveTask.events = m.flyoverEvents
    m.flyoverSaveTask.ObserveField("result", "OnFlyoverTaskResult")
    m.flyoverSaveTask.control = "run"
end sub

sub OnFlyoverTaskResult(event as object)
    result = event.GetData()
    if result = invalid
        return
    end if

    if result.operation = "load"
        m.flyoverLoadTask = invalid
        if result.ok = true and result.events <> invalid
            m.flyoverEvents = result.events
        else
            m.flyoverEvents = []
            print "Flight Lane debug: flyover history could not be loaded"
        end if
        m.flyoverHistoryLoaded = true
        historyChanged = PruneFlyoverEvents(CurrentEpochSeconds())
        UpdateFlyoverCount()
        if m.pendingFlyoverAircraft <> invalid
            pendingAircraft = m.pendingFlyoverAircraft
            m.pendingFlyoverAircraft = invalid
            TrackFlyovers(pendingAircraft)
        else if historyChanged
            SaveFlyoverHistory()
        end if
    else if result.operation = "save"
        m.flyoverSaveTask = invalid
        m.flyoverSaveInFlight = false
        if result.ok <> true
            print "Flight Lane debug: flyover history could not be saved"
        end if
        if m.flyoverSaveQueued
            SaveFlyoverHistory()
        end if
    end if
end sub

sub LoadRuntimeSettings()
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "load"
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub LoadLocalSession()
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "loadAuth"
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub SaveLocalSession(auth as object)
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "saveAuth"
    m.settingsTask.settings = auth
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub ClearLocalSession()
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "clearAuth"
    m.settingsTask.ObserveField("result", "OnSettingsResult")
    m.settingsTask.control = "run"
end sub

sub SaveRuntimeSettings(settings as object)
    m.settingsTask = CreateObject("roSGNode", "SettingsTask")
    m.settingsTask.operation = "save"
    m.settingsTask.settings = settings
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
            ApplyLocalSession(result.auth)
            LoadRuntimeSettings()
        else
            StartDeviceRegistration()
        end if
        return
    else if result.operation = "saveAuth"
        if result.ok = true
            ApplyLocalSession(result.auth)
            LoadRuntimeSettings()
        else
            m.statusLabel.text = "CONNECTION ERROR"
            m.statusLabel.color = "0xFCA5A5FF"
            ShowDeviceRegistrationRetry("Flight Lane could not save this Roku's secure connection.")
        end if
        return
    else if result.operation = "clearAuth"
        return
    end if

    if result.ok <> true
        m.statusLabel.text = "SETTINGS ERROR - " + StringOr(result.errorMessage, "Unable to save settings.")
        m.statusLabel.color = "0xFCA5A5FF"
        return
    end if

    if result.operation = "load"
        if result.configured = true
            ApplyRuntimeSettings(result.settings)
        else if m.isScreensaver
            ShowScreensaverSetupRequired()
        else
            ShowFirstLaunchSetup()
        end if
    else if result.operation = "save"
        ApplyRuntimeSettings(result.settings)
    end if
end sub

sub ApplyLocalSession(auth as object)
    m.localToken = StringOr(auth.token, "")
    m.localExpiresAt = StringOr(auth.expiresAt, "")
    m.registrationRequired = m.localToken = ""
    ConfigureMapAuthorization()
end sub

sub ConfigureMapAuthorization()
    headers = {}
    if m.localToken <> ""
        headers.Authorization = "Bearer " + m.localToken
    end if
    m.satelliteMap.SetHeaders(headers)
    for each mapPoster in m.closeupSatelliteMaps
        mapPoster.SetHeaders(headers)
    end for
end sub

sub StartDeviceRegistration()
    if m.registrationRequestInFlight
        return
    end if

    m.registrationRequired = true
    m.mainPanel.visible = false
    m.settingsPanel.visible = false
    m.setupPanel.visible = true
    m.setupMessage.text = "Connecting this Roku securely to Flight Lane. No additional access code is required."
    m.statusLabel.text = "CONNECTING FLIGHT LANE..."
    m.statusLabel.color = "0x7DD3FCFF"
    ShowFooterMessage("PLEASE WAIT WHILE FLIGHT LANE CONNECTS")
    m.top.SetFocus(true)
    m.registrationRequestInFlight = true
    m.registrationTask = StartApiTask("register", {})
end sub

sub ShowDeviceRegistrationRetry(message as string)
    m.registrationRequired = true
    m.mainPanel.visible = false
    m.settingsPanel.visible = false
    m.setupPanel.visible = true
    m.setupMessage.text = message + " Check the internet connection and press OK to try again."
    m.statusLabel.text = "CONNECTION ERROR"
    m.statusLabel.color = "0xFCA5A5FF"
    ShowFooterMessage("PRESS OK TO RETRY")
    m.top.SetFocus(true)
end sub

sub HandleRegistrationResult(result as object)
    if result.ok <> true
        ShowDeviceRegistrationRetry(StringOr(result.errorMessage, "Flight Lane could not connect this Roku."))
        return
    end if
    m.statusLabel.text = "SAVING SECURE CONNECTION..."
    SaveLocalSession(result.data)
end sub

sub ShowScreensaverSetupRequired()
    m.firstLaunchSetup = false
    m.mainPanel.visible = false
    m.settingsPanel.visible = false
    m.setupPanel.visible = true
    m.setupMessage.text = "Open Settings > Theme > Screensavers > Flight Lane > Change screensaver settings, then enter your home address."
    m.statusLabel.text = "SCREENSAVER SETUP REQUIRED"
    m.statusLabel.color = "0xFBBF24FF"
    ShowFooterMessage("FLIGHT LANE WILL START AFTER ITS LOCATION IS CONFIGURED")
    m.top.SetFocus(true)
end sub

sub ShowFirstLaunchSetup()
    m.registrationRequired = false
    m.firstLaunchSetup = true
    m.mainPanel.visible = false
    m.settingsPanel.visible = false
    m.setupPanel.visible = true
    m.setupMessage.text = "Enter your home address to build a private local flight radar. Your saved address stays on this Roku."
    m.statusLabel.text = "SETUP REQUIRED"
    m.statusLabel.color = "0xFBBF24FF"
    ShowFooterMessage("PRESS OK TO ENTER YOUR HOME ADDRESS")
    m.top.SetFocus(true)
    ShowAddressDialog()
end sub

sub ShowAddressDialog()
    if m.addressDialog <> invalid or m.geocodeRequestInFlight
        return
    end if

    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Enter your home address"
    dialog.message = ["Include street, city, state, and ZIP code."]
    dialog.buttons = ["Use this address", "Cancel"]
    dialog.keyboardDomain = "alphanumeric"
    if m.pendingSettings <> invalid
        dialog.text = StringOr(m.pendingSettings.address, "")
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
        StartGeocode(address)
    else if m.firstLaunchSetup
        m.setupPanel.visible = true
        m.top.SetFocus(true)
    else if m.settingsOpen
        m.settingsList.SetFocus(true)
    end if
end sub

sub StartGeocode(address as string)
    if m.geocodeRequestInFlight
        return
    end if
    m.geocodeRequestInFlight = true
    m.statusLabel.text = "FINDING HOME LOCATION..."
    m.statusLabel.color = "0x7DD3FCFF"
    m.geocodeTask = StartApiTask("geocode", { address: address })
end sub

sub HandleGeocodeResult(result as object)
    if result.ok <> true
        message = StringOr(result.errorMessage, "Address was not found.")
        m.statusLabel.text = "LOCATION ERROR"
        m.statusLabel.color = "0xFCA5A5FF"
        if m.firstLaunchSetup
            m.setupMessage.text = message + " Press OK to try again."
            m.setupPanel.visible = true
            m.top.SetFocus(true)
        else
            m.settingsAddressLabel.text = message
            m.settingsList.SetFocus(true)
        end if
        return
    end if

    data = result.data
    if m.pendingSettings = invalid
        defaultRadius = ClampNumber(m.config.radiusMiles, 1, 10)
        m.pendingSettings = {
            address: data.address
            latitude: data.latitude
            longitude: data.longitude
            radiusMiles: defaultRadius
            idleMinutes: 10
        }
    else
        m.pendingSettings.address = data.address
        m.pendingSettings.latitude = data.latitude
        m.pendingSettings.longitude = data.longitude
    end if

    if m.firstLaunchSetup
        m.statusLabel.text = "SAVING HOME LOCATION..."
        SaveRuntimeSettings(m.pendingSettings)
    else
        BuildSettingsContent()
        m.settingsList.SetFocus(true)
    end if
end sub

sub ApplyRuntimeSettings(settings as object)
    if settings = invalid
        ShowFirstLaunchSetup()
        return
    end if

    radiusMiles = ClampNumber(NumberOr(settings.radiusMiles, 4), 1, 10)
    idleMinutes = NumberOr(settings.idleMinutes, 10)
    if idleMinutes < 0
        idleMinutes = 0
    end if
    m.settings = {
        address: StringOr(settings.address, "Saved home location")
        latitude: NumberOr(settings.latitude, 0)
        longitude: NumberOr(settings.longitude, 0)
        radiusMiles: radiusMiles
        idleMinutes: idleMinutes
    }
    m.pendingSettings = invalid
    m.firstLaunchSetup = false
    m.settingsOpen = false
    m.displayMode = false
    m.locationRevision = m.locationRevision + 1

    m.config.hasLocation = true
    m.config.homeLatitude = m.settings.latitude
    m.config.homeLongitude = m.settings.longitude
    m.config.radiusMiles = m.settings.radiusMiles
    m.config.satelliteMapEnabled = m.config.flightLaneApiUrl <> "" and m.localToken <> ""
    CalculateRuntimeMapScale()

    m.aircraft = []
    m.selectedIndex = 0
    m.autoTrackClosest = true
    m.manualSelectedAircraftId = ""
    ResetInterpolationClock()
    m.detailCache = {}
    m.radarMarkers = []
    m.closeupMarkerRecord = invalid
    m.flyoverLastSeen = {}
    m.subtitle.text = "LIVE AIRCRAFT WITHIN " + FormatSettingNumber(m.config.radiusMiles) + " MILES OF HOME"
    m.setupPanel.visible = false
    m.settingsPanel.visible = false
    m.mainPanel.visible = true
    m.statusLabel.text = "STARTING LIVE RADAR..."
    m.statusLabel.color = "0x7DD3FCFF"
    UpdateFlyoverCount()
    UpdateFooter()
    EnsureOverviewMap()
    DrawRadar()
    if m.isScreensaver
        ShowFooterMessage("FLIGHT LANE SCREENSAVER  •  LIVE AIRCRAFT NEAR HOME")
        m.top.SetFocus(true)
    else
        m.aircraftList.SetFocus(true)
    end if
    RefreshNearbyAircraft()
    m.refreshTimer.control = "start"
    m.motionTimer.control = "start"
    if not m.isScreensaver
        ResetIdleTimer()
    end if
end sub

sub CalculateRuntimeMapScale()
    radiusMiles = m.config.radiusMiles
    mapMarginMiles = 0.2
    visibleHalfSpanMiles = radiusMiles + mapMarginMiles
    pixelsPerMile = 840.0 / (2.0 * visibleHalfSpanMiles)
    selectedZoom = 0
    mapLogicalSize = 640
    outerRadius = pixelsPerMile * radiusMiles

    if m.config.satelliteMapEnabled
        latitudeRadians = m.config.homeLatitude * 3.14159265358979 / 180
        for candidateZoom = 21 to 0 step -1
            metersPerLogicalPixel = 156543.03392 * Cos(latitudeRadians) / (2 ^ candidateZoom)
            candidateLogicalSize = (2.0 * visibleHalfSpanMiles * 1609.344) / metersPerLogicalPixel
            if candidateLogicalSize >= 128.0 and candidateLogicalSize <= 640.0
                selectedZoom = candidateZoom
                mapLogicalSize = Int(candidateLogicalSize + 0.5)
                actualHalfSpanMiles = (metersPerLogicalPixel * mapLogicalSize) / (2.0 * 1609.344)
                pixelsPerMile = 840.0 / (2.0 * actualHalfSpanMiles)
                outerRadius = pixelsPerMile * radiusMiles
                exit for
            end if
        end for
    end if

    m.config.mapZoom = selectedZoom
    m.config.mapLogicalSize = mapLogicalSize
    m.config.radarPixelsPerMile = pixelsPerMile
    radarDisplaySize = 840.0 * outerRadius / 390.0
    radarOffset = (840.0 - radarDisplaySize) / 2
    m.overviewRadar.width = radarDisplaySize
    m.overviewRadar.height = radarDisplaySize
    m.overviewRadar.translation = [radarOffset, radarOffset]
end sub

function ClampNumber(value as float, minimum as float, maximum as float) as float
    if value < minimum
        return minimum
    end if
    if value > maximum
        return maximum
    end if
    return value
end function

function CloneSettings(settings as object) as object
    return {
        address: settings.address
        latitude: settings.latitude
        longitude: settings.longitude
        radiusMiles: settings.radiusMiles
        idleMinutes: settings.idleMinutes
    }
end function

function FormatSettingNumber(value as float) as string
    if value = Int(value)
        return Int(value).ToStr()
    end if
    return RoundTo(value, 1).ToStr()
end function

sub OpenSettings()
    if m.settings = invalid
        return
    end if
    m.pendingSettings = CloneSettings(m.settings)
    m.settingsOpen = true
    m.settingsPanel.visible = true
    ShowSettingsFooter()
    BuildSettingsContent()
    m.settingsList.SetFocus(true)
end sub

sub CloseSettings()
    m.pendingSettings = invalid
    m.settingsOpen = false
    m.settingsPanel.visible = false
    UpdateFooter()
    m.aircraftList.SetFocus(true)
    ResetIdleTimer()
end sub

sub BuildSettingsContent()
    if m.pendingSettings = invalid
        return
    end if
    m.settingsAddressLabel.text = StringOr(m.pendingSettings.address, "No saved address")
    idleLabel = "Off"
    if m.pendingSettings.idleMinutes > 0
        idleLabel = FormatSettingNumber(m.pendingSettings.idleMinutes) + " min"
    end if
    rows = [
        "Change home address"
        "Detection radius: " + FormatSettingNumber(m.pendingSettings.radiusMiles) + " miles"
        "Idle display mode: " + idleLabel
        "Save and close"
    ]
    content = CreateObject("roSGNode", "ContentNode")
    for each rowTitle in rows
        item = content.CreateChild("ContentNode")
        item.title = rowTitle
    end for
    m.settingsList.content = content
end sub

sub OnSettingsItemSelected(event as object)
    if not m.settingsOpen
        return
    end if
    ActivateSettingsRow(event.GetData())
end sub

sub ActivateSettingsRow(index as integer)
    if index = 0
        ShowAddressDialog()
    else if index = 1
        AdjustSettingsValue(1)
    else if index = 2
        AdjustSettingsValue(1)
    else if index = 3
        m.statusLabel.text = "SAVING SETTINGS..."
        SaveRuntimeSettings(m.pendingSettings)
    end if
end sub

sub AdjustSettingsValue(direction as integer)
    index = m.settingsList.itemFocused
    if index = 1
        m.pendingSettings.radiusMiles = ClampNumber(m.pendingSettings.radiusMiles + direction, 1, 10)
    else if index = 2
        idleOptions = [0, 1, 5, 10, 15, 30, 60]
        selectedOption = 0
        for optionIndex = 0 to idleOptions.Count() - 1
            if idleOptions[optionIndex] = m.pendingSettings.idleMinutes
                selectedOption = optionIndex
                exit for
            end if
        end for
        selectedOption = selectedOption + direction
        if selectedOption < 0
            selectedOption = idleOptions.Count() - 1
        else if selectedOption >= idleOptions.Count()
            selectedOption = 0
        end if
        m.pendingSettings.idleMinutes = idleOptions[selectedOption]
    else
        return
    end if
    BuildSettingsContent()
    m.settingsList.jumpToItem = index
end sub

sub ResetIdleTimer()
    if m.settings = invalid
        return
    end if
    m.idleTimer.control = "stop"
    if m.settings.idleMinutes > 0
        m.idleTimer.duration = m.settings.idleMinutes * 60
        m.idleTimer.control = "start"
    end if
end sub

sub OnIdleTimer()
    if m.settings = invalid or m.settingsOpen or m.addressDialog <> invalid
        return
    end if
    m.displayMode = true
    m.autoTrackClosest = true
    m.manualSelectedAircraftId = ""
    if m.aircraft.Count() > 0
        m.selectedIndex = 0
        m.aircraftList.jumpToItem = 0
        UpdateSelection()
    end if
    ShowFooterMessage("DISPLAY MODE  •  LIVE RADAR CONTINUES  •  PRESS ANY REMOTE BUTTON FOR CONTROLS")
    m.top.SetFocus(true)
end sub

sub ExitDisplayMode()
    m.displayMode = false
    UpdateFooter()
    m.aircraftList.SetFocus(true)
    ResetIdleTimer()
end sub

sub UpdateFooter()
    m.footerControls.visible = true
    m.footerSettingsControls.visible = false
    m.footerLabel.visible = false
end sub

sub ShowSettingsFooter()
    m.footerControls.visible = false
    m.footerSettingsControls.visible = true
    m.footerLabel.visible = false
end sub

sub ShowFooterMessage(message as string)
    m.footerControls.visible = false
    m.footerSettingsControls.visible = false
    m.footerLabel.text = message
    m.footerLabel.visible = true
end sub

function SatelliteMapUrl(latitude as float, longitude as float, zoom as integer) as string
    url = m.config.flightLaneApiUrl + "/v1/map?latitude=" + latitude.ToStr()
    url = url + "&longitude=" + longitude.ToStr()
    url = url + "&zoom=" + zoom.ToStr()
    return url
end function

function OverviewSatelliteMapUrl(latitude as float, longitude as float, zoom as integer) as string
    url = SatelliteMapUrl(latitude, longitude, zoom)
    url = url + "&size=" + Int(m.config.mapLogicalSize).ToStr()
    return url
end function

sub EnsureOverviewMap()
    m.satelliteMap.width = 840
    m.satelliteMap.height = 840
    m.satelliteMap.translation = [0, 0]

    if m.config.satelliteMapEnabled
        mapUrl = OverviewSatelliteMapUrl(m.config.homeLatitude, m.config.homeLongitude, m.config.mapZoom)
        if m.satelliteMap.uri <> mapUrl
            print "Flight Lane debug: map mode=overview radius="; m.config.radiusMiles; "mi zoom="; m.config.mapZoom; " size="; m.config.mapLogicalSize
            m.satelliteRemoteRequested = true
            m.satelliteMap.uri = mapUrl
        end if
        m.rangeLabel.text = "Satellite · " + RoundTo(m.config.radiusMiles, 1).ToStr() + " mi from home"
    else
        m.rangeLabel.text = "Range · " + RoundTo(m.config.radiusMiles, 1).ToStr() + " mi from home"
    end if
end sub

sub UpdateCloseupPip(aircraft as object)
    if m.lowMemoryMode
        m.closeupPip.visible = false
        return
    end if
    currentPosition = InterpolatedAircraftPosition(aircraft)
    leadSeconds = m.config.refreshSeconds / 2
    mapCenterPosition = ProjectPosition(currentPosition, aircraft.heading, aircraft.speedKnots, leadSeconds)
    mapSettings = CloseupMapSettings(aircraft, mapCenterPosition)
    mapCenterPosition = SnapMapCenter(mapCenterPosition, mapSettings.snapMiles)
    m.closeupPip.visible = true
    m.closeupPipTitle.text = aircraft.callsign + " · 1,000 ft · Z" + mapSettings.zoom.ToStr()

    if m.config.satelliteMapEnabled
        centerCoordinates = CoordinatesFromHomeOffset(mapCenterPosition.eastMiles, mapCenterPosition.northMiles)
        mapUrl = SatelliteMapUrl(centerCoordinates.latitude, centerCoordinates.longitude, mapSettings.zoom)
        QueueCloseupMap(mapUrl, mapSettings.displaySize, mapCenterPosition, aircraft.callsign, mapSettings.zoom)
    else
        m.closeupImageryCredit.visible = false
    end if
    DrawCloseupPip()
end sub

sub QueueCloseupMap(mapUrl as string, displaySize as float, mapCenterPosition as object, callsign as string, zoom as integer)
    activeState = m.closeupMapStates[m.closeupMapActiveIndex]
    if activeState.url = mapUrl
        return
    end if
    if m.closeupMapPendingIndex >= 0 and m.closeupMapStates[m.closeupMapPendingIndex].url = mapUrl
        return
    end if

    pendingIndex = 1 - m.closeupMapActiveIndex
    baseOffset = (m.config.closeupViewportSize - displaySize) / 2
    m.closeupMapPendingIndex = pendingIndex
    m.closeupMapStates[pendingIndex] = {
        url: mapUrl
        centerEastMiles: mapCenterPosition.eastMiles
        centerNorthMiles: mapCenterPosition.northMiles
        baseOffset: baseOffset
    }

    pendingMap = m.closeupSatelliteMaps[pendingIndex]
    pendingMap.visible = false
    pendingMap.width = displaySize
    pendingMap.height = displaySize
    pendingMap.translation = [baseOffset, baseOffset]
    print "Flight Lane debug: PIP preloading="; callsign; " radius="; m.config.closeupRadiusFeet; "ft zoom="; zoom; " smooth=0.2s"
    pendingMap.uri = mapUrl
end sub

function CloseupMapSettings(aircraft as object, mapCenterPosition as object) as object
    speedMilesPerHour = aircraft.speedKnots * 1.150779
    projectedHalfTravelFeet = speedMilesPerHour * 5280 * m.config.refreshSeconds / 7200
    requiredHalfSpanFeet = m.config.closeupRadiusFeet + projectedHalfTravelFeet
    centerCoordinates = CoordinatesFromHomeOffset(mapCenterPosition.eastMiles, mapCenterPosition.northMiles)
    latitudeRadians = centerCoordinates.latitude * 3.14159265358979 / 180
    selectedZoom = 0
    metersPerLogicalPixel = 156543.03392 * Cos(latitudeRadians)
    ' The map center snaps to a grid of 1/4 the half-span, so reserve that much slack.
    ' Repeated refreshes then reuse one map URL instead of requesting a new provider image.
    snapFraction = 0.25
    for candidateZoom = m.config.closeupMaxZoom to 0 step -1
        candidateMetersPerLogicalPixel = 156543.03392 * Cos(latitudeRadians) / (2 ^ candidateZoom)
        availableHalfSpanFeet = candidateMetersPerLogicalPixel * 320 / 0.3048
        if availableHalfSpanFeet * (1 - (snapFraction / 2) - 0.02) >= requiredHalfSpanFeet
            selectedZoom = candidateZoom
            metersPerLogicalPixel = candidateMetersPerLogicalPixel
            exit for
        end if
    end for

    ' Size the grid from the home latitude so it stays fixed while the aircraft moves.
    homeLatitudeRadians = m.config.homeLatitude * 3.14159265358979 / 180
    homeHalfSpanFeet = 156543.03392 * Cos(homeLatitudeRadians) / (2 ^ selectedZoom) * 320 / 0.3048
    snapMiles = homeHalfSpanFeet * snapFraction / 5280

    nativePixelsPerFoot = (0.3048 / metersPerLogicalPixel) * (m.config.closeupViewportSize / 640)
    displaySize = m.config.closeupViewportSize * (m.config.closeupRadarPixelsPerFoot / nativePixelsPerFoot)
    return { zoom: selectedZoom, displaySize: displaySize, snapMiles: snapMiles }
end function

function SnapMapCenter(position as object, snapMiles as float) as object
    if snapMiles <= 0
        return position
    end if
    return {
        eastMiles: Int((position.eastMiles / snapMiles) + 0.5) * snapMiles
        northMiles: Int((position.northMiles / snapMiles) + 0.5) * snapMiles
    }
end function

function ProjectPosition(position as object, heading as float, speedKnots as float, secondsAhead as float) as object
    headingRadians = heading * 3.14159265358979 / 180
    traveledMiles = speedKnots * 1.150779 * secondsAhead / 3600
    return {
        eastMiles: position.eastMiles + (traveledMiles * Sin(headingRadians))
        northMiles: position.northMiles + (traveledMiles * Cos(headingRadians))
    }
end function

function CoordinatesFromHomeOffset(eastMiles as float, northMiles as float) as object
    latitude = m.config.homeLatitude + (northMiles / 69.0)
    latitudeRadians = m.config.homeLatitude * 3.14159265358979 / 180
    longitude = m.config.homeLongitude + (eastMiles / (69.172 * Cos(latitudeRadians)))
    return { latitude: latitude, longitude: longitude }
end function

sub OnSatelliteLoadStatus(event as object)
    print "Flight Lane debug: satellite map load status="; event.GetData()
    if event.GetData() = "failed" and m.satelliteRemoteRequested
        m.satelliteRemoteRequested = false
        m.satelliteMap.uri = "pkg:/images/map-backdrop.jpg"
        m.rangeLabel.text = "Radar · satellite map unavailable"
    end if
end sub

sub OnCloseupSatelliteMapALoadStatus(event as object)
    HandleCloseupSatelliteLoadStatus(0, StringOr(event.GetData(), ""))
end sub

sub OnCloseupSatelliteMapBLoadStatus(event as object)
    HandleCloseupSatelliteLoadStatus(1, StringOr(event.GetData(), ""))
end sub

sub HandleCloseupSatelliteLoadStatus(mapIndex as integer, loadStatus as string)
    print "Flight Lane debug: PIP map buffer="; mapIndex; " load status="; loadStatus
    if mapIndex <> m.closeupMapPendingIndex
        return
    end if
    if m.closeupSatelliteMaps[mapIndex].uri <> m.closeupMapStates[mapIndex].url
        return
    end if

    if loadStatus = "ready"
        oldIndex = m.closeupMapActiveIndex
        m.closeupSatelliteMaps[oldIndex].visible = false
        m.closeupMapActiveIndex = mapIndex
        m.closeupMapPendingIndex = -1
        m.closeupSatelliteMaps[mapIndex].visible = true
        m.closeupImageryCredit.visible = true
        PositionCloseupPip()
    else if loadStatus = "failed"
        m.closeupSatelliteMaps[mapIndex].visible = false
        m.closeupMapPendingIndex = -1
    end if
end sub

sub OnDetailCooldown()
    m.detailCooldownActive = false
    RequestSelectedFlightDetails()
end sub

sub OnRefreshTimer()
    RefreshNearbyAircraft()
end sub

sub OnClockTimer()
    UpdateCurrentClock()
    clock = CreateObject("roDateTime")
    clock.ToLocalTime()
    currentMinute = clock.GetMinutes()
    if currentMinute <> m.lastFlyoverPruneMinute
        m.lastFlyoverPruneMinute = currentMinute
        if m.flyoverHistoryLoaded and PruneFlyoverEvents(CurrentEpochSeconds())
            UpdateFlyoverCount()
            SaveFlyoverHistory()
        end if
    end if
end sub

sub UpdateCurrentClock()
    clock = CreateObject("roDateTime")
    clock.Mark()
    clock.ToLocalTime()

    months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    monthIndex = clock.GetMonth() - 1
    monthName = ""
    if monthIndex >= 0 and monthIndex < months.Count()
        monthName = months[monthIndex]
    end if
    weekday = UCase(Left(StringOr(clock.GetWeekday(), ""), 3))
    m.currentDateLabel.text = weekday + "  •  " + monthName + " " + clock.GetDayOfMonth().ToStr() + ", " + clock.GetYear().ToStr()

    hours = clock.GetHours()
    suffix = "AM"
    if hours >= 12
        suffix = "PM"
    end if
    displayHours = hours mod 12
    if displayHours = 0
        displayHours = 12
    end if
    m.currentTimeLabel.text = displayHours.ToStr() + ":" + PadTwo(clock.GetMinutes()) + ":" + PadTwo(clock.GetSeconds()) + " " + suffix
end sub

sub OnMotionTimer()
    if m.aircraft.Count() = 0
        return
    end if
    SyncInterpolationClock()
    AnimateRadarMarkers()
    AnimateCloseupPip()
    UpdateSelectedMotionDetails()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press
        return false
    end if
    if m.displayMode
        ExitDisplayMode()
        return true
    end if
    if m.settings <> invalid
        ResetIdleTimer()
    end if
    if m.addressDialog <> invalid
        return false
    end if
    if m.setupPanel.visible
        if key = "OK"
            if m.registrationRequired
                StartDeviceRegistration()
            else
                ShowAddressDialog()
            end if
            return true
        end if
        return false
    end if
    if m.settingsOpen
        if key = "back" or key = "options"
            CloseSettings()
            return true
        end if
        if key = "left"
            AdjustSettingsValue(-1)
            return true
        end if
        if key = "right"
            AdjustSettingsValue(1)
            return true
        end if
        return false
    end if
    if key = "options" and m.config.hasLocation = true
        OpenSettings()
        return true
    end if
    if key = "right" and m.config.hasLocation = true and m.aircraft.Count() > 0
        m.autoTrackClosest = true
        m.manualSelectedAircraftId = ""
        m.selectedIndex = 0
        m.aircraftList.jumpToItem = 0
        UpdateSelection()
        return true
    end if
    if (key = "up" or key = "down") and m.aircraft.Count() > 0
        m.autoTrackClosest = false
        return false
    end if
    if key = "OK" and m.config.hasLocation = true
        RefreshNearbyAircraft()
        return true
    end if
    return false
end function

sub RefreshNearbyAircraft()
    if m.nearbyRequestInFlight
        return
    end if
    m.nearbyRequestInFlight = true
    m.statusLabel.text = "UPDATING LIVE TRAFFIC…"
    m.statusLabel.color = "0x7DD3FCFF"
    m.nearbyTask = StartApiTask("nearby", {
        homeLatitude: m.config.homeLatitude
        homeLongitude: m.config.homeLongitude
        radiusMiles: m.config.radiusMiles
        requestRevision: m.locationRevision
    })
end sub

function StartApiTask(operation as string, params as object) as object
    if operation <> "register"
        params.localToken = m.localToken
    end if
    task = CreateObject("roSGNode", "FlightApiTask")
    task.operation = operation
    task.params = params
    task.ObserveField("result", "OnApiResult")
    task.control = "run"
    return task
end function

sub OnApiResult(event as object)
    result = event.GetData()
    if result = invalid
        return
    end if

    if result.operation <> "register" and result.code = 401
        m.nearbyRequestInFlight = false
        m.detailRequestInFlight = false
        m.photoRequestInFlight = false
        m.geocodeRequestInFlight = false
        m.localToken = ""
        m.refreshTimer.control = "stop"
        m.motionTimer.control = "stop"
        ClearLocalSession()
        StartDeviceRegistration()
        return
    end if

    if result.operation = "register"
        m.registrationRequestInFlight = false
        m.registrationTask = invalid
        HandleRegistrationResult(result)
    else if result.operation = "nearby"
        m.nearbyRequestInFlight = false
        m.nearbyTask = invalid
        if result.requestRevision = invalid or result.requestRevision = m.locationRevision
            HandleNearbyResult(result)
        end if
    else if result.operation = "flightDetails"
        m.detailRequestInFlight = false
        m.detailTask = invalid
        HandleFlightDetailsResult(result)
    else if result.operation = "aircraftPhoto"
        m.photoRequestInFlight = false
        m.photoTask = invalid
        HandleAircraftPhotoResult(result)
    else if result.operation = "geocode"
        m.geocodeRequestInFlight = false
        m.geocodeTask = invalid
        HandleGeocodeResult(result)
    end if
end sub

sub ShowDataSources(aircraftSource as string)
    parts = []
    if aircraftSource <> ""
        parts.Push("Data: " + aircraftSource)
    end if
    if m.config.satelliteMapEnabled
        parts.Push("Imagery: USGS")
    end if
    text = ""
    for each part in parts
        if text <> ""
            text = text + " · "
        end if
        text = text + part
    end for
    m.dataSourceLabel.text = text
end sub

' Shows this month's FlightAware AeroAPI spend when the local service has a FlightAware key.
sub ShowFlightAwareSpendNotice(spend as dynamic)
    if Type(spend) <> "roAssociativeArray"
        m.spendNoticeLabel.visible = false
        return
    end if

    state = StringOr(spend.state, "")
    cost = FormatDollars(spend.monthToDateCost)
    limit = FormatDollars(spend.limit)
    if state = "limit"
        m.spendNoticeLabel.text = "FlightAware API: " + cost + " of " + limit + " · paused"
        m.spendNoticeLabel.color = "0xFCA5A5FF"
    else if state = "warning"
        m.spendNoticeLabel.text = "FlightAware API: " + cost + " of " + limit
        m.spendNoticeLabel.color = "0xFBBF24FF"
    else if state = "unavailable"
        m.spendNoticeLabel.text = "FlightAware API: usage unknown · paused"
        m.spendNoticeLabel.color = "0xFBBF24FF"
    else if state = "checking"
        m.spendNoticeLabel.text = "FlightAware API: checking usage…"
        m.spendNoticeLabel.color = "0x8DA8C2FF"
    else
        m.spendNoticeLabel.text = "FlightAware API: " + cost + " of " + limit
        m.spendNoticeLabel.color = "0x8DA8C2FF"
    end if
    m.spendNoticeLabel.visible = true
end sub

sub HandleNearbyResult(result as object)
    if result.ok <> true
        m.statusLabel.text = "DATA ERROR — " + result.errorMessage
        m.statusLabel.color = "0xFCA5A5FF"
        return
    end if

    ShowDataSources(StringOr(result.data.source, ""))
    ShowFlightAwareSpendNotice(result.data.flightAware)

    counterAircraft = result.data.counterAircraft
    if counterAircraft = invalid
        counterAircraft = []
    end if
    TrackFlyovers(counterAircraft)

    previousId = m.manualSelectedAircraftId
    if previousId = "" and m.aircraft.Count() > 0 and m.selectedIndex >= 0 and m.selectedIndex < m.aircraft.Count()
        previousId = m.aircraft[m.selectedIndex].id
    end if

    nextAircraft = result.data.aircraft
    SyncInterpolationClock()
    ApplyAircraftPositionHandoffs(nextAircraft)
    m.aircraft = nextAircraft
    ResetInterpolationClock()
    print "Flight Lane debug: UI rendering "; m.aircraft.Count(); " aircraft"
    content = CreateObject("roSGNode", "ContentNode")
    newSelectedIndex = 0
    index = 0
    for each aircraft in m.aircraft
        item = content.CreateChild("ContentNode")
        item.title = AircraftListTitle(aircraft)
        if previousId <> "" and aircraft.id = previousId
            newSelectedIndex = index
        end if
        index = index + 1
    end for

    m.aircraftList.content = content
    m.emptyLabel.visible = m.aircraft.Count() = 0
    if m.aircraft.Count() > 0
        if m.autoTrackClosest
            newSelectedIndex = 0
        end if
        m.selectedIndex = newSelectedIndex
        m.aircraftList.jumpToItem = newSelectedIndex
        countLabel = m.aircraft.Count().ToStr() + " AIRCRAFT"
        if m.aircraft.Count() = 1
            countLabel = "1 AIRCRAFT"
        end if
        m.statusLabel.text = "LIVE  •  " + countLabel
    else
        m.selectedIndex = -1
        m.statusLabel.text = "LIVE  •  CLEAR WITHIN " + RoundTo(m.config.radiusMiles, 1).ToStr() + " MI"
    end if
    m.statusLabel.color = "0x86EFACFF"
    UpdateSelection()
end sub

sub TrackFlyovers(aircraftList as object)
    if aircraftList = invalid
        return
    end if
    if not m.flyoverHistoryLoaded
        m.pendingFlyoverAircraft = aircraftList
        return
    end if

    nowSeconds = CurrentEpochSeconds()
    scopeKey = FlyoverLocationKey()
    if scopeKey = ""
        return
    end if

    changed = PruneFlyoverEvents(nowSeconds)
    for each aircraft in aircraftList
        aircraftId = UCase(StringOr(aircraft.id, StringOr(aircraft.callsign, "")))
        if aircraftId <> ""
            trackerKey = scopeKey + "|" + aircraftId
            previousSeen = 0
            if m.flyoverLastSeen.DoesExist(trackerKey)
                previousSeen = NumberOr(m.flyoverLastSeen[trackerKey], 0)
            end if
            m.flyoverLastSeen[trackerKey] = nowSeconds

            isNewPass = previousSeen <= 0 or (nowSeconds - previousSeen) >= m.flyoverReentrySeconds
            if isNewPass and not WasFlyoverRecentlyRecorded(trackerKey, nowSeconds)
                m.flyoverEvents.Push({
                    key: trackerKey
                    locationKey: scopeKey
                    aircraftId: aircraftId
                    callsign: StringOr(aircraft.callsign, aircraftId)
                    timestamp: nowSeconds
                })
                changed = true
                print "Flight Lane debug: recorded 4mi flyover "; StringOr(aircraft.callsign, aircraftId)
            end if
        end if
    end for

    UpdateFlyoverCount()
    if changed
        SaveFlyoverHistory()
    end if
end sub

function WasFlyoverRecentlyRecorded(trackerKey as string, nowSeconds as longinteger) as boolean
    for index = m.flyoverEvents.Count() - 1 to 0 step -1
        flyover = m.flyoverEvents[index]
        if flyover <> invalid and StringOr(flyover.key, "") = trackerKey
            eventSeconds = NumberOr(flyover.timestamp, 0)
            return (nowSeconds - eventSeconds) < m.flyoverReentrySeconds
        end if
    end for
    return false
end function

function PruneFlyoverEvents(nowSeconds as longinteger) as boolean
    retainedEvents = []
    cutoffSeconds = nowSeconds - m.flyoverWindowSeconds
    changed = false
    for each flyover in m.flyoverEvents
        eventSeconds = 0
        if flyover <> invalid
            eventSeconds = NumberOr(flyover.timestamp, 0)
        end if
        if eventSeconds >= cutoffSeconds and eventSeconds <= (nowSeconds + 300)
            retainedEvents.Push(flyover)
        else
            changed = true
        end if
    end for
    m.flyoverEvents = retainedEvents
    return changed
end function

sub UpdateFlyoverCount()
    if m.flyoverCountLabel = invalid
        return
    end if
    scopeKey = FlyoverLocationKey()
    flyoverCount = 0
    if scopeKey <> ""
        for each flyover in m.flyoverEvents
            if flyover <> invalid and StringOr(flyover.locationKey, "") = scopeKey
                flyoverCount = flyoverCount + 1
            end if
        end for
    end if
    m.flyoverCountLabel.text = flyoverCount.ToStr()
end sub

function FlyoverLocationKey() as string
    if m.settings = invalid
        return ""
    end if
    latitudeKey = RoundTo(NumberOr(m.settings.latitude, 0), 4).ToStr()
    longitudeKey = RoundTo(NumberOr(m.settings.longitude, 0), 4).ToStr()
    return latitudeKey + "," + longitudeKey
end function

function CurrentEpochSeconds() as longinteger
    clock = CreateObject("roDateTime")
    return clock.AsSeconds()
end function

function AircraftListTitle(aircraft as object) as string
    return aircraft.callsign + "  " + RoundTo(aircraft.distanceMiles, 1).ToStr() + " mi  " + FormatAltitude(aircraft.altitudeFt, aircraft.onGround)
end function

sub OnAircraftFocused(event as object)
    index = event.GetData()
    if index < 0 or index >= m.aircraft.Count()
        return
    end if
    m.selectedIndex = index
    if not m.autoTrackClosest or index > 0
        m.autoTrackClosest = false
        m.manualSelectedAircraftId = m.aircraft[index].id
    end if
    UpdateSelection()
end sub

sub UpdateSelection()
    if m.selectedIndex < 0 or m.selectedIndex >= m.aircraft.Count()
        ShowEmptyDetails()
        EnsureOverviewMap()
        DrawRadar()
        return
    end if

    aircraft = m.aircraft[m.selectedIndex]
    m.selectedTitle.text = aircraft.callsign
    ShowAirlineIdentity(aircraft)
    metaParts = []
    if aircraft.registration <> ""
        metaParts.Push(aircraft.registration)
    end if
    if aircraft.aircraftType <> ""
        metaParts.Push(aircraft.aircraftType)
    end if
    if aircraft.registration = "" and aircraft.aircraftType = ""
        metaParts.Push("ICAO " + UCase(aircraft.id))
    end if
    m.selectedMeta.text = JoinText(metaParts, " · ")
    m.speedValue.text = FormatSpeed(aircraft.speedKnots)
    m.headingValue.text = CompassDirection(aircraft.heading) + "  " + FormatWhole(aircraft.heading) + "°"
    m.phaseValue.text = aircraft.phase + VerticalRateLabel(aircraft.verticalRateFpm)
    UpdateSelectedMotionDetails()
    EnsureOverviewMap()
    UpdateCloseupPip(aircraft)
    ApplyOrRequestAircraftPhoto(aircraft)

    ApplyCachedFlightDetails(aircraft)
    DrawRadar()
end sub

sub UpdateSelectedMotionDetails()
    if m.selectedIndex < 0 or m.selectedIndex >= m.aircraft.Count()
        return
    end if

    aircraft = m.aircraft[m.selectedIndex]
    position = InterpolatedAircraftPosition(aircraft)
    distanceMiles = Sqr((position.eastMiles * position.eastMiles) + (position.northMiles * position.northMiles))
    altitudeFt = aircraft.altitudeFt
    if not aircraft.onGround
        altitudeFt = altitudeFt + (aircraft.verticalRateFpm * position.elapsedSeconds / 60)
        if altitudeFt < 0
            altitudeFt = 0
        end if
    end if
    m.altitudeValue.text = FormatAltitude(altitudeFt, aircraft.onGround)
    m.distanceValue.text = FormatMiles(distanceMiles)

    remainingMinutes = aircraft.closestEtaMinutes - (position.elapsedSeconds / 60)
    if aircraft.approaching and remainingMinutes > 0 and remainingMinutes <= 30
        m.projectionValue.text = "Projected closest approach: " + FormatMiles(aircraft.closestMiles) + " in " + RoundTo(remainingMinutes, 1).ToStr() + " min"
    else
        m.projectionValue.text = "Current track is moving away from the house."
    end if
end sub

sub ShowEmptyDetails()
    m.closeupPip.visible = false
    m.closeupMarkerRecord = invalid
    m.selectedTitle.text = "No nearby aircraft"
    m.selectedMeta.text = "The radar will refresh automatically."
    m.airlineBadgeBackground.visible = false
    m.airlineCodeValue.visible = false
    m.airlineNameValue.visible = false
    HideAircraftPhoto()
    m.altitudeValue.text = "—"
    m.speedValue.text = "—"
    m.distanceValue.text = "—"
    m.headingValue.text = "—"
    m.phaseValue.text = "—"
    m.projectionValue.text = "No projected paths inside the current range."
    m.routeValue.text = "—"
    m.flightStatusValue.text = ""
    m.departureValue.text = ""
    m.arrivalValue.text = ""
end sub

sub ShowAirlineIdentity(aircraft as object)
    m.airlineBadgeBackground.visible = true
    m.airlineCodeValue.visible = true
    m.airlineNameValue.visible = true
    m.airlineBadgeBackground.color = StringOr(aircraft.airlineColor, "0x24415AFF")
    m.airlineCodeValue.text = StringOr(aircraft.airlineCode, "GEN")
    m.airlineCodeValue.color = StringOr(aircraft.airlineTextColor, "0xFFFFFFFF")
    m.airlineNameValue.text = StringOr(aircraft.airlineName, StringOr(aircraft.operatorName, "Private / unidentified"))
    m.airlineNameValue.color = StringOr(aircraft.airlineTextColor, "0xFFFFFFFF")
end sub

sub ApplyOrRequestAircraftPhoto(aircraft as object)
    if m.lowMemoryMode
        HideAircraftPhoto()
        return
    end if
    registration = UCase(StringOr(aircraft.registration, ""))
    if registration = "" or m.config.flightLaneApiUrl = ""
        HideAircraftPhoto()
        return
    end if

    if m.photoCache.DoesExist(registration)
        ShowAircraftPhoto(m.photoCache[registration])
        return
    end if

    HideAircraftPhoto()
    if m.photoRequestInFlight
        return
    end if
    m.photoRequestInFlight = true
    m.photoTask = StartApiTask("aircraftPhoto", { registration: registration })
end sub

sub HandleAircraftPhotoResult(result as object)
    registration = UCase(StringOr(result.registration, ""))
    if result.ok = true
        registration = UCase(StringOr(result.data.registration, registration))
        if registration <> ""
            m.photoCache[registration] = result.data
        end if
    else if registration <> ""
        m.photoCache[registration] = { registration: registration, available: false }
    end if

    if m.selectedIndex >= 0 and m.selectedIndex < m.aircraft.Count()
        ApplyOrRequestAircraftPhoto(m.aircraft[m.selectedIndex])
    else
        HideAircraftPhoto()
    end if
end sub

sub ShowAircraftPhoto(photo as object)
    if photo.available <> true or StringOr(photo.imageUrl, "") = ""
        HideAircraftPhoto()
        return
    end if

    m.aircraftPhotoAttribution.text = StringOr(photo.attribution, "(c) Planespotters.net")
    if m.aircraftPhoto.uri <> photo.imageUrl
        m.aircraftPhoto.uri = photo.imageUrl
    end if
    m.aircraftPhotoCard.visible = true
    SetAircraftIdentityLayout(true)
end sub

sub HideAircraftPhoto()
    m.aircraftPhotoCard.visible = false
    SetAircraftIdentityLayout(false)
end sub

sub SetAircraftIdentityLayout(hasPhoto as boolean)
    if hasPhoto
        m.selectedTitle.width = 260
        m.selectedMeta.width = 260
        m.airlineBadgeBackground.width = 260
        m.airlineNameValue.width = 170
    else
        m.selectedTitle.width = 520
        m.selectedMeta.width = 520
        m.airlineBadgeBackground.width = 530
        m.airlineNameValue.width = 430
    end if
end sub

sub OnAircraftPhotoLoadStatus(event as object)
    if LCase(StringOr(event.GetData(), "")) <> "failed"
        return
    end if

    if m.selectedIndex >= 0 and m.selectedIndex < m.aircraft.Count()
        registration = UCase(StringOr(m.aircraft[m.selectedIndex].registration, ""))
        if registration <> ""
            m.photoCache[registration] = { registration: registration, available: false }
        end if
    end if
    HideAircraftPhoto()
end sub

sub ApplyCachedFlightDetails(aircraft as object)
    if m.detailCache.DoesExist(aircraft.id)
        ShowFlightDetails(m.detailCache[aircraft.id])
        RequestSelectedFlightDetails()
        return
    end if

    if m.config.flightLaneApiUrl = "" or m.localToken = ""
        m.routeValue.text = "Route details unavailable"
        m.flightStatusValue.text = "Local service connection required"
        m.departureValue.text = ""
        m.arrivalValue.text = ""
        return
    end if

    m.routeValue.text = "Looking up route…"
    m.flightStatusValue.text = ""
    m.departureValue.text = ""
    m.arrivalValue.text = ""
    RequestSelectedFlightDetails()
end sub

sub RequestSelectedFlightDetails()
    if m.detailRequestInFlight or m.detailCooldownActive or m.selectedIndex < 0 or m.selectedIndex >= m.aircraft.Count()
        return
    end if
    aircraft = m.aircraft[m.selectedIndex]
    if not NeedsFlightDetailLookup(aircraft)
        return
    end if
    if Left(aircraft.callsign, 8) = "Unknown "
        m.detailCache[aircraft.id] = { available: false }
        ShowFlightDetails(m.detailCache[aircraft.id])
        return
    end if

    m.detailRequestInFlight = true
    m.detailCooldownActive = true
    m.detailCooldownTimer.control = "start"
    m.detailTask = StartApiTask("flightDetails", {
        lookupKey: aircraft.id
        callsign: aircraft.callsign
        manual: not m.autoTrackClosest
    })
end sub

' Free route data is fetched for any selection. Billed live status (FlightAware, when the
' local service has a key) is requested only once per aircraft, and only when chosen manually.
function NeedsFlightDetailLookup(aircraft as object) as boolean
    if not m.detailCache.DoesExist(aircraft.id)
        return true
    end if
    if m.autoTrackClosest
        return false
    end if
    cached = m.detailCache[aircraft.id]
    return IsTrue(cached.liveStatusAvailable) and not IsTrue(cached.liveStatus) and not IsTrue(cached.manualLookup)
end function

sub HandleFlightDetailsResult(result as object)
    lookupKey = StringOr(result.lookupKey, "")
    if result.ok = true
        lookupKey = StringOr(result.data.lookupKey, lookupKey)
        if lookupKey <> ""
            m.detailCache[lookupKey] = result.data
        end if
    else if lookupKey <> ""
        m.detailCache[lookupKey] = { available: false, errorMessage: result.errorMessage }
    end if

    if m.selectedIndex >= 0 and m.selectedIndex < m.aircraft.Count()
        selected = m.aircraft[m.selectedIndex]
        if m.detailCache.DoesExist(selected.id)
            ShowFlightDetails(m.detailCache[selected.id])
        end if
        RequestSelectedFlightDetails()
    end if
end sub

sub ShowFlightDetails(details as object)
    if details.available <> true
        m.routeValue.text = "Route unavailable"
        if IsNonEmptyString(details.errorMessage)
            m.flightStatusValue.text = details.errorMessage
        else
            m.flightStatusValue.text = "Private or unmatched flight"
        end if
        m.departureValue.text = ""
        m.arrivalValue.text = ""
        return
    end if

    m.routeValue.text = details.origin + "  →  " + details.destination
    if details.status <> ""
        m.flightStatusValue.text = details.status
        if IsNonEmptyString(details.source)
            m.flightStatusValue.text = m.flightStatusValue.text + " · " + details.source
        end if
    else
        m.flightStatusValue.text = "Typical route"
        if IsNonEmptyString(details.source)
            m.flightStatusValue.text = m.flightStatusValue.text + " · " + details.source
        end if
    end if
    departureTime = PreferredTime(details.actualOff, details.estimatedOff, details.scheduledOff)
    arrivalTime = PreferredTime(details.actualOn, details.estimatedOn, details.scheduledOn)
    m.departureValue.text = TimeLine("Takeoff", departureTime)
    m.arrivalValue.text = TimeLine("Landing", arrivalTime)
end sub

function PreferredTime(actualValue as dynamic, estimatedValue as dynamic, scheduledValue as dynamic) as string
    if IsNonEmptyString(actualValue)
        return FriendlyTime(actualValue) + " actual"
    end if
    if IsNonEmptyString(estimatedValue)
        return FriendlyTime(estimatedValue) + " est."
    end if
    if IsNonEmptyString(scheduledValue)
        return FriendlyTime(scheduledValue) + " sched."
    end if
    return ""
end function

function FriendlyTime(value as string) as string
    if value.Len() >= 16
        return Mid(value, 6, 5) + " " + Mid(value, 12, 5) + "Z"
    end if
    return value
end function

function TimeLine(label as string, value as string) as string
    if value = ""
        return label + ": unavailable"
    end if
    return label + ": " + value
end function

function VerticalRateLabel(rate as float) as string
    if Abs(rate) < 100
        return ""
    end if
    if rate > 0
        return "  •  +" + FormatWhole(rate) + " ft/min"
    end if
    return "  •  " + FormatWhole(rate) + " ft/min"
end function

function JoinText(values as object, separator as string) as string
    output = ""
    for each value in values
        if output <> ""
            output = output + separator
        end if
        output = output + value
    end for
    return output
end function

sub ApplyAircraftPositionHandoffs(nextAircraft as object)
    if nextAircraft = invalid or nextAircraft.Count() = 0 or m.aircraft.Count() = 0
        return
    end if

    previousPositions = {}
    for each previousAircraft in m.aircraft
        previousId = StringOr(previousAircraft.id, "")
        if previousId <> ""
            previousPositions[previousId] = InterpolatedAircraftPosition(previousAircraft)
        end if
    end for

    for each aircraft in nextAircraft
        aircraft.handoffEastMiles = 0
        aircraft.handoffNorthMiles = 0
        aircraft.handoffSeconds = 0
        aircraftId = StringOr(aircraft.id, "")
        if aircraftId <> "" and previousPositions.DoesExist(aircraftId)
            previousPosition = previousPositions[aircraftId]
            authoritativePosition = ProjectedAircraftPosition(aircraft, 0)
            correctionEast = previousPosition.eastMiles - authoritativePosition.eastMiles
            correctionNorth = previousPosition.northMiles - authoritativePosition.northMiles
            correctionMiles = Sqr((correctionEast * correctionEast) + (correctionNorth * correctionNorth))

            if correctionMiles >= 0.002
                speedMilesPerSecond = aircraft.speedKnots * 1.150779 / 3600
                handoffSeconds = m.config.refreshSeconds
                if speedMilesPerSecond > 0.001
                    handoffSeconds = correctionMiles / (speedMilesPerSecond * 0.4)
                end if
                if handoffSeconds < 2
                    handoffSeconds = 2
                end if
                aircraft.handoffEastMiles = correctionEast
                aircraft.handoffNorthMiles = correctionNorth
                aircraft.handoffSeconds = handoffSeconds
                print "Flight Lane debug: smoothing refresh correction for "; aircraft.callsign; " distance="; RoundTo(correctionMiles, 3); "mi duration="; RoundTo(aircraft.handoffSeconds, 1); "s"
            end if
        end if
    end for
end sub

sub ResetInterpolationClock()
    if m.interpolationClock = invalid
        m.interpolationClock = CreateObject("roTimespan")
    end if
    m.interpolationClock.Mark()
    m.interpolationSeconds = 0
end sub

sub SyncInterpolationClock()
    if m.interpolationClock = invalid
        ResetInterpolationClock()
        return
    end if
    m.interpolationSeconds = m.interpolationClock.TotalMilliseconds() / 1000.0
end sub

sub DrawRadar()
    childCount = m.markerLayer.GetChildCount()
    if childCount > 0
        m.markerLayer.RemoveChildrenIndex(childCount, 0)
    end if

    m.radarMarkers = []
    center = 420.0
    scale = m.config.radarPixelsPerMile
    maxMarkers = m.aircraft.Count()
    if maxMarkers > 24
        maxMarkers = 24
    end if

    if maxMarkers > 0
        for index = 0 to maxMarkers - 1
            aircraft = m.aircraft[index]
            position = InterpolatedAircraftPosition(aircraft)
            selected = index = m.selectedIndex
            marker = CreateObject("roSGNode", "Group")
            marker.translation = [center + (position.eastMiles * scale), center - (position.northMiles * scale)]

            projectionDistance = DistanceToRadarEdge(position.eastMiles, position.northMiles, aircraft.heading, m.config.radiusMiles)
            path = marker.CreateChild("Rectangle")
            path.width = projectionDistance * scale
            path.height = 3
            path.translation = [0, -1]
            path.scaleRotateCenter = [0, 1]
            path.rotation = (90 - aircraft.heading) * 3.14159265358979 / 180
            path.visible = projectionDistance > 0
            if selected
                path.color = "0xFBBF2488"
            else
                path.color = "0x38BDF855"
            end if

            dot = marker.CreateChild("Rectangle")
            if selected
                dot.width = 22
                dot.height = 22
                dot.translation = [-11, -11]
                dot.color = "0xFBBF24FF"
            else
                dot.width = 14
                dot.height = 14
                dot.translation = [-7, -7]
                dot.color = "0x38BDF8FF"
            end if

            label = marker.CreateChild("Label")
            label.translation = [16, -20]
            label.width = 190
            label.height = 40
            label.text = aircraft.callsign
            if selected
                label.color = "0xFFFFFFFF"
            else
                label.color = "0x9BDCFBFF"
            end if

            m.markerLayer.AppendChild(marker)
            m.radarMarkers.Push({ group: marker, path: path, aircraftIndex: index })
        end for
    end if

    home = CreateObject("roSGNode", "Group")
    home.translation = [center, center]
    homeDot = home.CreateChild("Rectangle")
    homeDot.width = 18
    homeDot.height = 18
    homeDot.translation = [-9, -9]
    homeDot.color = "0xFB7185FF"
    homeLabel = home.CreateChild("Label")
    homeLabel.translation = [14, 8]
    homeLabel.width = 120
    homeLabel.height = 34
    homeLabel.text = "HOME"
    homeLabel.color = "0xFDA4AFFF"
    m.markerLayer.AppendChild(home)
end sub

sub DrawCloseupPip()
    childCount = m.closeupMarkerLayer.GetChildCount()
    if childCount > 0
        m.closeupMarkerLayer.RemoveChildrenIndex(childCount, 0)
    end if
    if m.selectedIndex < 0 or m.selectedIndex >= m.aircraft.Count()
        m.closeupMarkerRecord = invalid
        return
    end if

    aircraft = m.aircraft[m.selectedIndex]
    center = m.config.closeupViewportSize / 2
    radiusMiles = m.config.closeupRadiusFeet / 5280.0
    scale = m.config.closeupRadarPixelsPerFoot * 5280.0

    path = m.closeupMarkerLayer.CreateChild("Rectangle")
    path.width = radiusMiles * scale
    path.height = 4
    path.translation = [center, center - 2]
    path.scaleRotateCenter = [0, 2]
    path.rotation = (90 - aircraft.heading) * 3.14159265358979 / 180
    path.color = "0xFBBF24CC"

    marker = CreateObject("roSGNode", "Group")
    marker.translation = [center, center]
    dot = marker.CreateChild("Rectangle")
    dot.width = 18
    dot.height = 18
    dot.translation = [-9, -9]
    dot.color = "0xFBBF24FF"
    m.closeupMarkerLayer.AppendChild(marker)

    home = CreateObject("roSGNode", "Group")
    home.visible = false
    homeDot = home.CreateChild("Rectangle")
    homeDot.width = 12
    homeDot.height = 12
    homeDot.translation = [-6, -6]
    homeDot.color = "0xFB7185FF"
    homeLabel = home.CreateChild("Label")
    homeLabel.translation = [8, 4]
    homeLabel.width = 80
    homeLabel.height = 26
    homeLabel.text = "HOME"
    homeLabel.color = "0xFFFFFFFF"
    m.closeupMarkerLayer.AppendChild(home)

    m.closeupMarkerRecord = {
        group: marker
        path: path
        home: home
        aircraftIndex: m.selectedIndex
    }
    PositionCloseupPip()
end sub

sub AnimateRadarMarkers()
    if m.radarMarkers = invalid or m.radarMarkers.Count() = 0
        return
    end if

    center = 420.0
    scale = m.config.radarPixelsPerMile
    for each markerRecord in m.radarMarkers
        index = markerRecord.aircraftIndex
        if index >= 0 and index < m.aircraft.Count()
            aircraft = m.aircraft[index]
            position = InterpolatedAircraftPosition(aircraft)
            distanceMiles = Sqr((position.eastMiles * position.eastMiles) + (position.northMiles * position.northMiles))
            markerRecord.group.visible = distanceMiles <= m.config.radiusMiles
            if markerRecord.group.visible
                markerRecord.group.translation = [center + (position.eastMiles * scale), center - (position.northMiles * scale)]
                projectionDistance = DistanceToRadarEdge(position.eastMiles, position.northMiles, aircraft.heading, m.config.radiusMiles)
                markerRecord.path.width = projectionDistance * scale
                markerRecord.path.visible = projectionDistance > 0
            end if
        end if
    end for
end sub

sub AnimateCloseupPip()
    if m.closeupMarkerRecord = invalid
        return
    end if

    index = m.closeupMarkerRecord.aircraftIndex
    if index < 0 or index >= m.aircraft.Count()
        return
    end if

    PositionCloseupPip()
end sub

sub PositionCloseupPip()
    if m.closeupMarkerRecord = invalid
        return
    end if

    index = m.closeupMarkerRecord.aircraftIndex
    if index < 0 or index >= m.aircraft.Count()
        return
    end if

    aircraft = m.aircraft[index]
    position = InterpolatedAircraftPosition(aircraft)
    scale = m.config.closeupRadarPixelsPerFoot * 5280.0
    activeState = m.closeupMapStates[m.closeupMapActiveIndex]
    if IsNumericValue(activeState.centerEastMiles) and IsNumericValue(activeState.centerNorthMiles)
        deltaEastMiles = position.eastMiles - activeState.centerEastMiles
        deltaNorthMiles = position.northMiles - activeState.centerNorthMiles
        m.closeupSatelliteMaps[m.closeupMapActiveIndex].translation = [
            activeState.baseOffset - (deltaEastMiles * scale),
            activeState.baseOffset + (deltaNorthMiles * scale)
        ]
    end if

    center = m.config.closeupViewportSize / 2
    m.closeupMarkerRecord.group.translation = [center, center]
    m.closeupMarkerRecord.path.rotation = (90 - aircraft.heading) * 3.14159265358979 / 180

    radiusMiles = m.config.closeupRadiusFeet / 5280.0
    homeEastMiles = 0 - position.eastMiles
    homeNorthMiles = 0 - position.northMiles
    homeDistanceMiles = Sqr((homeEastMiles * homeEastMiles) + (homeNorthMiles * homeNorthMiles))
    m.closeupMarkerRecord.home.visible = homeDistanceMiles <= radiusMiles
    if m.closeupMarkerRecord.home.visible
        m.closeupMarkerRecord.home.translation = [
            center + (homeEastMiles * scale),
            center - (homeNorthMiles * scale)
        ]
    end if
end sub

function ProjectedAircraftPosition(aircraft as object, animationSeconds as float) as object
    elapsedSeconds = animationSeconds + aircraft.sourceAgeSeconds
    maximumSeconds = m.config.refreshSeconds * 2
    if maximumSeconds > 60
        maximumSeconds = 60
    end if
    if elapsedSeconds > maximumSeconds
        elapsedSeconds = maximumSeconds
    end if

    headingRadians = aircraft.heading * 3.14159265358979 / 180
    traveledMiles = aircraft.speedKnots * 1.150779 * elapsedSeconds / 3600
    return {
        eastMiles: aircraft.eastMiles + (traveledMiles * Sin(headingRadians))
        northMiles: aircraft.northMiles + (traveledMiles * Cos(headingRadians))
        elapsedSeconds: elapsedSeconds
    }
end function

function InterpolatedAircraftPosition(aircraft as object) as object
    position = ProjectedAircraftPosition(aircraft, m.interpolationSeconds)
    handoffSeconds = NumberOr(aircraft.handoffSeconds, 0)
    handoffElapsedSeconds = position.elapsedSeconds - aircraft.sourceAgeSeconds
    if handoffElapsedSeconds < 0
        handoffElapsedSeconds = 0
    end if
    if handoffSeconds > 0 and handoffElapsedSeconds < handoffSeconds
        handoffFactor = 1 - (handoffElapsedSeconds / handoffSeconds)
        position.eastMiles = position.eastMiles + (NumberOr(aircraft.handoffEastMiles, 0) * handoffFactor)
        position.northMiles = position.northMiles + (NumberOr(aircraft.handoffNorthMiles, 0) * handoffFactor)
    end if
    return position
end function

function DistanceToRadarEdge(eastMiles as float, northMiles as float, heading as float, radiusMiles as float) as float
    headingRadians = heading * 3.14159265358979 / 180
    eastUnit = Sin(headingRadians)
    northUnit = Cos(headingRadians)
    b = 2 * ((eastMiles * eastUnit) + (northMiles * northUnit))
    c = (eastMiles * eastMiles) + (northMiles * northMiles) - (radiusMiles * radiusMiles)
    discriminant = (b * b) - (4 * c)
    if discriminant < 0
        return 0
    end if
    distance = (-b + Sqr(discriminant)) / 2
    if distance < 0
        return 0
    end if
    return distance
end function
