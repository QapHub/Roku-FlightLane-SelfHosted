sub init()
    m.top.functionName = "RunSettingsOperation"
end sub

sub RunSettingsOperation()
    operation = m.top.operation
    if operation = "load"
        m.top.result = LoadSettings()
    else if operation = "save"
        m.top.result = SaveSettings(m.top.settings)
    else if operation = "loadAuth"
        m.top.result = LoadLocalSession()
    else if operation = "saveAuth"
        m.top.result = SaveLocalSession(m.top.settings)
    else if operation = "clearAuth"
        m.top.result = ClearLocalSession()
    else
        m.top.result = { ok: false, operation: operation, errorMessage: "Unknown settings operation." }
    end if
end sub

function LoadSettings() as object
    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid or not section.Exists("settings")
        return { ok: true, operation: "load", configured: false }
    end if

    saved = ParseJson(section.Read("settings"))
    if saved = invalid or saved.latitude = invalid or saved.longitude = invalid
        return { ok: true, operation: "load", configured: false }
    end if
    return { ok: true, operation: "load", configured: true, settings: saved }
end function

function LoadLocalSession() as object
    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid or not section.Exists("localSession")
        return { ok: true, operation: "loadAuth", configured: false }
    end if
    saved = ParseJson(section.Read("localSession"))
    if saved = invalid or not IsNonEmptyText(saved.token)
        return { ok: true, operation: "loadAuth", configured: false }
    end if
    return { ok: true, operation: "loadAuth", configured: true, auth: saved }
end function

function SaveLocalSession(auth as object) as object
    if auth = invalid or not IsNonEmptyText(auth.token)
        return { ok: false, operation: "saveAuth", errorMessage: "Flight Lane connection data is incomplete." }
    end if
    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid
        return { ok: false, operation: "saveAuth", errorMessage: "Roku settings storage is unavailable." }
    end if
    if not section.Write("localSession", FormatJson(auth)) or not section.Flush()
        return { ok: false, operation: "saveAuth", errorMessage: "Unable to save the Flight Lane connection on this Roku." }
    end if
    return { ok: true, operation: "saveAuth", auth: auth }
end function

function ClearLocalSession() as object
    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid
        return { ok: false, operation: "clearAuth", errorMessage: "Roku settings storage is unavailable." }
    end if
    if section.Exists("localSession")
        section.Delete("localSession")
        section.Flush()
    end if
    return { ok: true, operation: "clearAuth" }
end function

function IsNonEmptyText(value as dynamic) as boolean
    valueType = Type(value)
    return (valueType = "roString" or valueType = "String") and value.Trim() <> ""
end function

function SaveSettings(settings as object) as object
    if settings = invalid or settings.latitude = invalid or settings.longitude = invalid
        return { ok: false, operation: "save", errorMessage: "Location settings are incomplete." }
    end if

    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid
        return { ok: false, operation: "save", errorMessage: "Roku settings storage is unavailable." }
    end if
    if not section.Write("settings", FormatJson(settings)) or not section.Flush()
        return { ok: false, operation: "save", errorMessage: "Unable to save settings on this Roku." }
    end if
    return { ok: true, operation: "save", settings: settings }
end function
