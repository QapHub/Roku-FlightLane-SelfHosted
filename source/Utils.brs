function IsNonEmptyString(value as dynamic) as boolean
    valueType = Type(value)
    return (valueType = "roString" or valueType = "String") and value.Trim() <> ""
end function
function IsTrue(value as dynamic) as boolean
    valueType = Type(value)
    return (valueType = "roBoolean" or valueType = "Boolean") and value
end function

function IsNumericValue(value as dynamic) as boolean
    valueType = Type(value)
    return valueType = "roInt" or valueType = "Integer" or valueType = "roFloat" or valueType = "Float" or valueType = "roDouble" or valueType = "Double" or valueType = "roLongInteger" or valueType = "LongInteger"
end function

function NumberOr(value as dynamic, fallback as float) as float
    if IsNumericValue(value)
        return value * 1.0
    end if
    if IsNonEmptyString(value)
        return Val(value)
    end if
    return fallback
end function

function StringOr(value as dynamic, fallback as string) as string
    if IsNonEmptyString(value)
        return value.Trim()
    end if
    return fallback
end function

function RoundTo(value as float, decimals as integer) as float
    factor = 10 ^ decimals
    if value < 0
        return Int((value * factor) - 0.5) / factor
    end if
    return Int((value * factor) + 0.5) / factor
end function

function FormatWhole(value as float) as string
    rounded = Int(value + 0.5)
    return rounded.ToStr()
end function

function FormatMiles(value as float) as string
    return RoundTo(value, 1).ToStr() + " mi"
end function

function FormatAltitude(value as float, onGround as boolean) as string
    if onGround
        return "Ground"
    end if
    return FormatWhole(value) + " ft"
end function

function FormatSpeed(value as float) as string
    if value <= 0
        return "—"
    end if
    return FormatWhole(value) + " kt"
end function

function CompassDirection(degrees as float) as string
    names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    normalized = degrees
    while normalized < 0
        normalized = normalized + 360
    end while
    while normalized >= 360
        normalized = normalized - 360
    end while
    index = Int((normalized + 22.5) / 45) mod 8
    return names[index]
end function

function UrlEncode(value as dynamic) as string
    if value = invalid
        return ""
    end if
    transfer = CreateObject("roUrlTransfer")
    return transfer.Escape(value.ToStr())
end function

function PadTwo(value as integer) as string
    if value < 10
        return "0" + value.ToStr()
    end if
    return value.ToStr()
end function

function LocalClock(epochSeconds as dynamic) as string
    if not IsNumericValue(epochSeconds)
        return "now"
    end if
    clock = CreateObject("roDateTime")
    clock.FromSeconds(Int(epochSeconds))
    clock.ToLocalTime()
    return PadTwo(clock.GetHours()) + ":" + PadTwo(clock.GetMinutes())
end function
