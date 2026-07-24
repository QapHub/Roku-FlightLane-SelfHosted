function CreateFlightLaneMemoryMonitor(port as object) as object
    state = {
        appMonitor: invalid
        deviceInfo: invalid
        appWarningsEnabled: false
        initialUsagePercent: -1
        availableMemoryKb: -1
        channelMemoryLimit: invalid
    }

    appMonitor = CreateObject("roAppMemoryMonitor")
    if appMonitor <> invalid
        appMonitor.SetMessagePort(port)
        state.appMonitor = appMonitor
        state.appWarningsEnabled = appMonitor.EnableMemoryWarningEvent(true)
        state.initialUsagePercent = appMonitor.GetMemoryLimitPercent()
        state.availableMemoryKb = appMonitor.GetChannelAvailableMemory()
        state.channelMemoryLimit = appMonitor.GetChannelMemoryLimit()
        print "Flight Lane memory monitor: usage="; state.initialUsagePercent; "% available="; state.availableMemoryKb; "KB"
    end if

    if state.appWarningsEnabled <> true
        deviceInfo = CreateObject("roDeviceInfo")
        if deviceInfo <> invalid
            deviceInfo.SetMessagePort(port)
            deviceInfo.EnableLowGeneralMemoryEvent(true)
            state.deviceInfo = deviceInfo
            print "Flight Lane memory monitor: using general-memory fallback"
        end if
    end if

    return state
end function

function HandleFlightLaneMemoryMessage(message as object, scene as object) as boolean
    messageType = Type(message)
    if messageType = "roAppMemoryNotificationEvent"
        info = message.GetInfo()
        if info = invalid
            return true
        end if
        usagePercent = info.Lookup("memoryUsagePercent")
        if usagePercent = invalid
            usagePercent = info.Lookup("MemoryUsagePercent")
        end if
        if usagePercent <> invalid
            usagePercent = Int(usagePercent)
            print "Flight Lane memory warning: app usage="; usagePercent; "%"
            if scene <> invalid and scene.HasField("memoryUsagePercent")
                scene.memoryUsagePercent = usagePercent
            end if
        end if
        return true
    else if messageType = "roDeviceInfoEvent"
        info = message.GetInfo()
        if info = invalid
            return false
        end if
        generalLevel = info.Lookup("generalMemoryLevel")
        if generalLevel <> invalid
            generalLevel = LCase(generalLevel.ToStr())
            print "Flight Lane memory warning: general level="; generalLevel
            if scene <> invalid and scene.HasField("generalMemoryLevel")
                scene.generalMemoryLevel = generalLevel
            end if
            return true
        end if
    end if
    return false
end function
