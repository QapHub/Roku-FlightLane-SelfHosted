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

' Whole amounts drop the cents: $10, $5.40.
function FormatDollars(value as dynamic) as string
    cents = Int((NumberOr(value, 0) * 100) + 0.5)
    if cents mod 100 = 0
        return "$" + Int(cents / 100).ToStr()
    end if
    return "$" + Int(cents / 100).ToStr() + "." + PadTwo(cents mod 100)
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

' BrightScript has only Atn(), so this provides the two-argument arctangent in radians.
function Atan2(y as float, x as float) as float
    pi = 3.14159265358979
    if x > 0
        return Atn(y / x)
    else if x < 0 and y >= 0
        return Atn(y / x) + pi
    else if x < 0
        return Atn(y / x) - pi
    else if y > 0
        return pi / 2
    else if y < 0
        return -pi / 2
    end if
    return 0
end function

' Wraps an angle in degrees into -180..180.
function WrapDegrees(value as float) as float
    wrapped = value
    while wrapped > 180
        wrapped = wrapped - 360
    end while
    while wrapped < -180
        wrapped = wrapped + 360
    end while
    return wrapped
end function

' Moves an aircraft forward along a constant-rate turn (degrees per second, positive = right),
' then straight. When the autopilot-selected heading (navHeading, or -1) lies ahead in the
' turn, the turn stops there. Turns are capped at 180 degrees.
function AdvancePosition(eastMiles as float, northMiles as float, heading as float, speedKnots as float, turnRate as float, navHeading as float, seconds as float) as object
    speedMilesPerSecond = speedKnots * 1.150779 / 3600
    radiansPerDegree = 3.14159265358979 / 180
    east = eastMiles
    north = northMiles
    currentHeading = heading
    remaining = seconds

    if Abs(turnRate) >= 0.05 and remaining > 0
        turnSeconds = remaining
        if Abs(180 / turnRate) < turnSeconds
            turnSeconds = Abs(180 / turnRate)
        end if
        if navHeading >= 0
            toTarget = WrapDegrees(navHeading - heading)
            if toTarget * turnRate > 0 and toTarget / turnRate < turnSeconds
                turnSeconds = toTarget / turnRate
            end if
        end if
        rate = turnRate * radiansPerDegree
        startRadians = heading * radiansPerDegree
        endRadians = startRadians + (rate * turnSeconds)
        east = east + ((speedMilesPerSecond / rate) * (Cos(startRadians) - Cos(endRadians)))
        north = north + ((speedMilesPerSecond / rate) * (Sin(endRadians) - Sin(startRadians)))
        currentHeading = heading + (turnRate * turnSeconds)
        remaining = remaining - turnSeconds
    end if

    if remaining > 0
        headingRadians = currentHeading * radiansPerDegree
        east = east + (speedMilesPerSecond * remaining * Sin(headingRadians))
        north = north + (speedMilesPerSecond * remaining * Cos(headingRadians))
    end if
    return { eastMiles: east, northMiles: north, heading: currentHeading }
end function
