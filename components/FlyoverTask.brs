sub init()
    m.top.functionName = "RunFlyoverOperation"
end sub

sub RunFlyoverOperation()
    operation = m.top.operation
    if operation = "load"
        m.top.result = LoadFlyoverEvents()
    else if operation = "save"
        m.top.result = SaveFlyoverEvents(m.top.events)
    else
        m.top.result = { ok: false, operation: operation, errorMessage: "Unknown flyover operation." }
    end if
end sub

function LoadFlyoverEvents() as object
    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid or not section.Exists("flyoverEventsV1")
        return { ok: true, operation: "load", events: [] }
    end if

    savedEvents = ParseJson(section.Read("flyoverEventsV1"))
    if savedEvents = invalid or Type(savedEvents) <> "roArray"
        return { ok: true, operation: "load", events: [] }
    end if
    return { ok: true, operation: "load", events: savedEvents }
end function

function SaveFlyoverEvents(events as object) as object
    if events = invalid
        events = []
    end if
    section = CreateObject("roRegistrySection", "FlightLane")
    if section = invalid
        return { ok: false, operation: "save", errorMessage: "Roku flyover storage is unavailable." }
    end if
    if not section.Write("flyoverEventsV1", FormatJson(events)) or not section.Flush()
        return { ok: false, operation: "save", errorMessage: "Unable to save flyover history." }
    end if
    return { ok: true, operation: "save" }
end function
