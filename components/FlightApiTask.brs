sub init()
    m.top.functionName = "RunApiOperation"
end sub

sub RunApiOperation()
    operation = m.top.operation
    params = m.top.params
    if params = invalid
        params = {}
    end if

    if operation = "register"
        output = RegisterDevice(params)
    else if operation = "nearby"
        output = FetchNearbyAircraft(params)
    else if operation = "flightDetails"
        output = FetchFlightDetails(params)
    else if operation = "aircraftPhoto"
        output = FetchAircraftPhoto(params)
    else if operation = "geocode"
        output = GeocodeAddress(params)
    else
        output = FailureResult(operation, "Unknown API operation.", 0)
    end if

    if IsNumericValue(params.requestRevision)
        output.requestRevision = params.requestRevision
    end if

    m.top.result = output
end sub

function RegisterDevice(params as object) as object
    config = GetAppConfig()
    if config.flightLaneApiUrl = ""
        return FailureResult("register", "Flight Lane service is not configured.", 0)
    end if

    deviceInfo = CreateObject("roDeviceInfo")
    deviceId = deviceInfo.GetChannelClientId()
    if deviceId = invalid or deviceId = ""
        return FailureResult("register", "This Roku did not provide a device identifier.", 0)
    end if

    registrationPayload = CreateObject("roAssociativeArray")
    registrationPayload.AddReplace("deviceId", deviceId)
    response = HttpJsonPost(config.flightLaneApiUrl + "/v1/register", {
        "Accept": "application/json"
        "User-Agent": "FlightLane/1.0.0 Roku"
    }, FormatJson(registrationPayload))
    data = ParseJsonBody(response.body)
    if response.code < 200 or response.code >= 300 or data = invalid or data.ok <> true
        return FailureResult("register", ResponseError(response, data), response.code)
    end if
    if StringOr(data.token, "") = ""
        return FailureResult("register", "The registration service returned an invalid response.", response.code)
    end if

    return SuccessResult("register", {
        token: data.token
        expiresAt: StringOr(data.expiresAt, "")
    })
end function

function FetchNearbyAircraft(params as object) as object
    config = GetAppConfig()
    if IsNumericValue(params.homeLatitude)
        config.homeLatitude = params.homeLatitude
    end if
    if IsNumericValue(params.homeLongitude)
        config.homeLongitude = params.homeLongitude
    end if
    if IsNumericValue(params.radiusMiles)
        config.radiusMiles = params.radiusMiles
    end if
    displayRadiusMiles = config.radiusMiles
    counterRadiusMiles = 4.0
    queryRadiusMiles = displayRadiusMiles
    if counterRadiusMiles > queryRadiusMiles
        queryRadiusMiles = counterRadiusMiles
    end if
    config.radiusMiles = queryRadiusMiles
    config.hasLocation = IsNumericValue(params.homeLatitude) and IsNumericValue(params.homeLongitude)
    if config.hasLocation <> true
        return FailureResult("nearby", "Home coordinates have not been configured.", 0)
    end if

    if config.flightLaneApiUrl = ""
        return FailureResult("nearby", "Flight Lane service is not configured.", 0)
    end if
    url = config.flightLaneApiUrl + "/v1/aircraft/nearby?latitude=" + config.homeLatitude.ToStr()
    url = url + "&longitude=" + config.homeLongitude.ToStr()
    url = url + "&radiusMiles=" + RoundTo(config.radiusMiles, 2).ToStr()
    if IsNumericValue(params.pollSeconds)
        url = url + "&pollSeconds=" + Int(params.pollSeconds).ToStr()
    end if

    response = HttpRequest(url, AuthHeaders(params))
    data = ParseJsonBody(response.body)
    print "Flight Lane debug: nearby provider HTTP "; response.code
    if response.code < 200 or response.code >= 300 or data = invalid
        return FailureResult("nearby", ResponseError(response, data), response.code)
    end if

    sourceAircraft = data.ac
    if sourceAircraft = invalid
        sourceAircraft = data.aircraft
    end if

    payloadAgeSeconds = ProviderPayloadAgeSeconds(data.now)
    aircraft = []
    counterAircraft = []
    rawCount = 0
    missingPositionCount = 0
    outsideRadiusCount = 0
    if sourceAircraft <> invalid
        for each rawAircraft in sourceAircraft
            rawCount = rawCount + 1
            if not IsNumericValue(rawAircraft.lat) or not IsNumericValue(rawAircraft.lon)
                missingPositionCount = missingPositionCount + 1
            else
                normalized = NormalizeAircraft(rawAircraft, config, payloadAgeSeconds)
                if normalized <> invalid
                    if normalized.distanceMiles <= displayRadiusMiles
                        aircraft.Push(normalized)
                    end if
                    if normalized.distanceMiles <= counterRadiusMiles
                        counterAircraft.Push(normalized)
                    end if
                else
                    outsideRadiusCount = outsideRadiusCount + 1
                end if
            end if
        end for
    end if
    SortAircraftByDistance(aircraft)
    SortAircraftByDistance(counterAircraft)
    print "Flight Lane debug: raw="; rawCount; " usable="; aircraft.Count(); " counter_4mi="; counterAircraft.Count(); " missing_position="; missingPositionCount; " outside_statute_radius="; outsideRadiusCount; " payload_age="; RoundTo(payloadAgeSeconds, 2); "s"
    for each visibleAircraft in aircraft
        print "Flight Lane debug: visible "; visibleAircraft.callsign; " distance="; RoundTo(visibleAircraft.distanceMiles, 1); "mi altitude="; visibleAircraft.altitudeFt; "ft heading="; visibleAircraft.heading; " age="; visibleAircraft.sourceAgeSeconds; "s"
    end for

    return SuccessResult("nearby", {
        aircraft: aircraft
        counterAircraft: counterAircraft
        updatedAt: data.now
        source: StringOr(data.flightLaneSource, "")
        flightAware: data.flightAware
    })
end function

function GeocodeAddress(params as object) as object
    config = GetAppConfig()
    address = StringOr(params.address, "")
    if address = ""
        return FailureResult("geocode", "Enter a street address, city, state, and ZIP code.", 0)
    end if
    if config.flightLaneApiUrl = ""
        return FailureResult("geocode", "Flight Lane service is not configured.", 0)
    end if

    url = config.flightLaneApiUrl + "/v1/geocode"
    response = HttpJsonPost(url, AuthHeaders(params), FormatJson({ address: address }))
    data = ParseJsonBody(response.body)
    if response.code < 200 or response.code >= 300 or data = invalid
        return FailureResult("geocode", ResponseError(response, data), response.code)
    end if
    if data.status <> "OK" or data.results = invalid or data.results.Count() = 0
        message = StringOr(data.error_message, "Address was not found. Include city, state, and ZIP code.")
        return FailureResult("geocode", message, response.code)
    end if

    match = data.results[0]
    if match.geometry = invalid or match.geometry.location = invalid
        return FailureResult("geocode", "The address result did not include coordinates.", response.code)
    end if
    location = match.geometry.location
    return SuccessResult("geocode", {
        address: StringOr(match.formatted_address, address)
        latitude: NumberOr(location.lat, 0)
        longitude: NumberOr(location.lng, 0)
    })
end function

function ProviderPayloadAgeSeconds(providerNow as dynamic) as float
    if not IsNumericValue(providerNow)
        return 0
    end if

    providerSeconds = NumberOr(providerNow, 0)
    if providerSeconds > 100000000000
        providerSeconds = providerSeconds / 1000
    end if
    if providerSeconds < 1000000000
        return 0
    end if
    clock = CreateObject("roDateTime")
    ageSeconds = clock.AsSeconds() - providerSeconds
    if ageSeconds < 0
        return 0
    end if
    if ageSeconds > 60
        return 60
    end if
    return ageSeconds
end function

function NormalizeAircraft(rawAircraft as object, config as object, payloadAgeSeconds as float) as dynamic
    if not IsNumericValue(rawAircraft.lat) or not IsNumericValue(rawAircraft.lon)
        return invalid
    end if

    latitude = NumberOr(rawAircraft.lat, 0)
    longitude = NumberOr(rawAircraft.lon, 0)
    latitudeRadians = config.homeLatitude * 3.14159265358979 / 180
    northMiles = (latitude - config.homeLatitude) * 69.0
    eastMiles = (longitude - config.homeLongitude) * 69.172 * Cos(latitudeRadians)
    distanceMiles = Sqr((northMiles * northMiles) + (eastMiles * eastMiles))
    if distanceMiles > config.radiusMiles
        return invalid
    end if

    altitudeField = rawAircraft.alt_baro
    onGround = false
    if IsNonEmptyString(altitudeField)
        onGround = LCase(altitudeField.Trim()) = "ground"
    end if
    altitudeFt = NumberOr(altitudeField, NumberOr(rawAircraft.alt_geom, 0))
    speedKnots = NumberOr(rawAircraft.gs, 0)
    heading = NumberOr(rawAircraft.track, NumberOr(rawAircraft.true_heading, 0))
    verticalRate = NumberOr(rawAircraft.baro_rate, NumberOr(rawAircraft.geom_rate, 0))
    callsign = StringOr(rawAircraft.flight, "")
    registration = StringOr(rawAircraft.r, "")
    if callsign = ""
        callsign = registration
    end if
    if callsign = ""
        callsign = "Unknown " + StringOr(rawAircraft.hex, "aircraft")
    end if

    operatorName = StringOr(rawAircraft.ownOp, "")
    airline = AirlineIdentity(callsign, operatorName)
    phase = EstimatePhase(onGround, altitudeFt, verticalRate)
    turnRate = NumberOr(rawAircraft.fl_turn_rate, 0)
    navHeading = NumberOr(rawAircraft.nav_heading, -1)
    if onGround
        turnRate = 0
        navHeading = -1
    end if
    closest = ClosestApproach(eastMiles, northMiles, heading, speedKnots, turnRate, navHeading)

    ' Earlier reported positions from the local service, converted like the current one.
    trail = []
    if Type(rawAircraft.fl_trail) = "roArray"
        for each point in rawAircraft.fl_trail
            if Type(point) = "roArray" and point.Count() >= 2 and IsNumericValue(point[0]) and IsNumericValue(point[1])
                ageSeconds = 0
                if point.Count() >= 3
                    ageSeconds = NumberOr(point[2], 0)
                end if
                trail.Push({
                    northMiles: (point[0] - config.homeLatitude) * 69.0
                    eastMiles: (point[1] - config.homeLongitude) * 69.172 * Cos(latitudeRadians)
                    ageSeconds: ageSeconds
                })
            end if
        end for
    end if
    sourceAgeSeconds = NumberOr(rawAircraft.seen_pos, NumberOr(rawAircraft.seen, 0)) + payloadAgeSeconds
    if sourceAgeSeconds < 0
        sourceAgeSeconds = 0
    else if sourceAgeSeconds > 60
        sourceAgeSeconds = 60
    end if

    return {
        id: StringOr(rawAircraft.hex, callsign)
        callsign: callsign
        registration: registration
        aircraftType: StringOr(rawAircraft.t, "")
        aircraftDescription: StringOr(rawAircraft.desc, "")
        operatorName: operatorName
        airlineName: airline.name
        airlineCode: airline.code
        airlineColor: airline.color
        airlineTextColor: airline.textColor
        latitude: latitude
        longitude: longitude
        eastMiles: eastMiles
        northMiles: northMiles
        distanceMiles: distanceMiles
        altitudeFt: altitudeFt
        onGround: onGround
        speedKnots: speedKnots
        heading: heading
        turnRate: turnRate
        navHeading: navHeading
        trail: trail
        verticalRateFpm: verticalRate
        phase: phase
        closestMiles: closest.distanceMiles
        closestEtaMinutes: closest.etaMinutes
        approaching: closest.approaching
        emergency: StringOr(rawAircraft.emergency, "none")
        squawk: StringOr(rawAircraft.squawk, "")
        sourceAgeSeconds: sourceAgeSeconds
    }
end function

function AirlineIdentity(callsign as string, operatorName as string) as object
    prefix = UCase(Left(StringOr(callsign, ""), 3))
    identity = { code: prefix, name: operatorName, color: "0x24415AFF", textColor: "0xFFFFFFFF" }

    if prefix = "DAL"
        identity = { code: "DAL", name: "Delta Air Lines", color: "0xC8102EFF", textColor: "0xFFFFFFFF" }
    else if prefix = "SWA"
        identity = { code: "SWA", name: "Southwest Airlines", color: "0x304CB2FF", textColor: "0xFFFFFFFF" }
    else if prefix = "UAL"
        identity = { code: "UAL", name: "United Airlines", color: "0x005DAAFF", textColor: "0xFFFFFFFF" }
    else if prefix = "AAL"
        identity = { code: "AAL", name: "American Airlines", color: "0x0078D2FF", textColor: "0xFFFFFFFF" }
    else if prefix = "JBU"
        identity = { code: "JBU", name: "JetBlue Airways", color: "0x003876FF", textColor: "0xFFFFFFFF" }
    else if prefix = "FFT"
        identity = { code: "FFT", name: "Frontier Airlines", color: "0x2E7D32FF", textColor: "0xFFFFFFFF" }
    else if prefix = "NKS"
        identity = { code: "NKS", name: "Spirit Airlines", color: "0xFFD400FF", textColor: "0x171717FF" }
    else if prefix = "ASA"
        identity = { code: "ASA", name: "Alaska Airlines", color: "0x01426AFF", textColor: "0xFFFFFFFF" }
    else if prefix = "FDX"
        identity = { code: "FDX", name: "FedEx Express", color: "0x4D148CFF", textColor: "0xFFFFFFFF" }
    else if prefix = "UPS"
        identity = { code: "UPS", name: "UPS Airlines", color: "0x351C15FF", textColor: "0xFFFFFFFF" }
    else if prefix = "GTI"
        identity = { code: "GTI", name: "Atlas Air", color: "0x1464A5FF", textColor: "0xFFFFFFFF" }
    else if prefix = "EDV"
        identity = { code: "EDV", name: "Endeavor Air / Delta", color: "0xC8102EFF", textColor: "0xFFFFFFFF" }
    else if prefix = "SKW"
        identity = { code: "SKW", name: "SkyWest Airlines", color: "0x245B8DFF", textColor: "0xFFFFFFFF" }
    else if prefix = "RPA"
        identity = { code: "RPA", name: "Republic Airways", color: "0x315C7DFF", textColor: "0xFFFFFFFF" }
    else if prefix = "JIA"
        identity = { code: "JIA", name: "PSA Airlines", color: "0x1676B8FF", textColor: "0xFFFFFFFF" }
    else if prefix = "PDT"
        identity = { code: "PDT", name: "Piedmont Airlines", color: "0x1676B8FF", textColor: "0xFFFFFFFF" }
    else if prefix = "GJS"
        identity = { code: "GJS", name: "GoJet Airlines", color: "0x245B8DFF", textColor: "0xFFFFFFFF" }
    else if prefix = "EJA"
        identity = { code: "EJA", name: "NetJets", color: "0x303B45FF", textColor: "0xFFFFFFFF" }
    else if prefix = "LXJ"
        identity = { code: "LXJ", name: "Flexjet", color: "0x303B45FF", textColor: "0xFFFFFFFF" }
    end if

    if identity.name = ""
        identity.name = "Private / unidentified"
        identity.code = "GEN"
    else if not IsAlphabeticPrefix(identity.code)
        identity.code = "OP"
    end if
    return identity
end function

function IsAlphabeticPrefix(value as string) as boolean
    if Len(value) <> 3
        return false
    end if
    for index = 1 to 3
        character = Asc(Mid(value, index, 1))
        if character < 65 or character > 90
            return false
        end if
    end for
    return true
end function

function EstimatePhase(onGround as boolean, altitudeFt as float, verticalRate as float) as string
    if onGround
        return "On ground"
    end if
    if altitudeFt < 5000 and verticalRate >= 300
        return "After takeoff"
    end if
    if altitudeFt < 7000 and verticalRate <= -300
        return "On approach"
    end if
    if verticalRate >= 500
        return "Climbing"
    end if
    if verticalRate <= -500
        return "Descending"
    end if
    return "Level flight"
end function

' Closest approach to home along the projected path (curving with the current turn), sampled
' every 20 seconds for up to 10 minutes.
function ClosestApproach(eastMiles as float, northMiles as float, heading as float, speedKnots as float, turnRate as float, navHeading as float) as object
    startDistance = Sqr((eastMiles * eastMiles) + (northMiles * northMiles))
    if speedKnots <= 1
        return { approaching: false, distanceMiles: startDistance, etaMinutes: -1 }
    end if

    bestDistance = startDistance
    bestSeconds = 0
    for seconds = 20 to 600 step 20
        position = AdvancePosition(eastMiles, northMiles, heading, speedKnots, turnRate, navHeading, seconds)
        distance = Sqr((position.eastMiles * position.eastMiles) + (position.northMiles * position.northMiles))
        if distance < bestDistance
            bestDistance = distance
            bestSeconds = seconds
        end if
    end for
    if bestSeconds = 0
        return { approaching: false, distanceMiles: startDistance, etaMinutes: -1 }
    end if
    return { approaching: true, distanceMiles: bestDistance, etaMinutes: bestSeconds / 60 }
end function

sub SortAircraftByDistance(aircraft as object)
    if aircraft.Count() < 2
        return
    end if
    for index = 1 to aircraft.Count() - 1
        current = aircraft[index]
        position = index
        while position > 0 and aircraft[position - 1].distanceMiles > current.distanceMiles
            aircraft[position] = aircraft[position - 1]
            position = position - 1
        end while
        aircraft[position] = current
    end for
end sub

function FetchFlightDetails(params as object) as object
    config = GetAppConfig()
    lookupKey = StringOr(params.lookupKey, "")
    callsign = StringOr(params.callsign, "")
    if config.flightLaneApiUrl = "" or callsign = ""
        return SuccessResult("flightDetails", { lookupKey: lookupKey, available: false })
    end if

    url = config.flightLaneApiUrl + "/v1/flights/" + UrlEncode(callsign)
    response = HttpRequest(url, AuthHeaders(params))
    print "Flight Lane debug: route lookup for "; callsign; " HTTP "; response.code
    data = ParseJsonBody(response.body)
    if response.code < 200 or response.code >= 300 or data = invalid
        result = FailureResult("flightDetails", ResponseError(response, data), response.code)
        result.lookupKey = lookupKey
        return result
    end if

    if data.flights = invalid or data.flights.Count() = 0
        return SuccessResult("flightDetails", { lookupKey: lookupKey, available: false })
    end if

    selectedFlight = data.flights[0]
    for each flight in data.flights
        if flight.cancelled <> true and flight.actual_on = invalid and flight.actual_in = invalid
            selectedFlight = flight
            exit for
        end if
    end for

    return SuccessResult("flightDetails", {
        lookupKey: lookupKey
        available: true
        ident: StringOr(selectedFlight.ident_iata, StringOr(selectedFlight.ident, callsign))
        registration: StringOr(selectedFlight.registration, "")
        aircraftType: StringOr(selectedFlight.aircraft_type, "")
        origin: AirportCode(selectedFlight.origin)
        destination: AirportCode(selectedFlight.destination)
        status: StringOr(selectedFlight.status, "")
        scheduledOff: StringOr(selectedFlight.scheduled_off, "")
        estimatedOff: StringOr(selectedFlight.estimated_off, "")
        actualOff: StringOr(selectedFlight.actual_off, "")
        scheduledOn: StringOr(selectedFlight.scheduled_on, "")
        estimatedOn: StringOr(selectedFlight.estimated_on, "")
        actualOn: StringOr(selectedFlight.actual_on, "")
        routeDistanceMiles: NumberOr(selectedFlight.route_distance, 0)
        source: StringOr(data.source, "")
    })
end function

function FetchAircraftPhoto(params as object) as object
    config = GetAppConfig()
    registration = UCase(StringOr(params.registration, ""))
    if registration = "" or config.flightLaneApiUrl = ""
        return SuccessResult("aircraftPhoto", { registration: registration, available: false })
    end if

    url = config.flightLaneApiUrl + "/v1/aircraft-photo/" + UrlEncode(registration)
    response = HttpRequest(url, AuthHeaders(params))
    data = ParseJsonBody(response.body)
    print "Flight Lane debug: photo lookup for "; registration; " HTTP "; response.code
    if response.code < 200 or response.code >= 300 or data = invalid
        result = FailureResult("aircraftPhoto", ResponseError(response, data), response.code)
        result.registration = registration
        return result
    end if
    if data.ok <> true
        result = FailureResult("aircraftPhoto", ResponseError(response, data), response.code)
        result.registration = registration
        return result
    end if

    return SuccessResult("aircraftPhoto", {
        registration: registration
        available: data.available = true
        imageUrl: StringOr(data.imageUrl, "")
        sourceUrl: StringOr(data.sourceUrl, "")
        photographer: StringOr(data.photographer, "")
        attribution: StringOr(data.attribution, "(c) Planespotters.net")
        width: NumberOr(data.width, 0)
        height: NumberOr(data.height, 0)
    })
end function

function AirportCode(airport as dynamic) as string
    if airport = invalid
        return "Unknown"
    end if
    code = StringOr(airport.code_iata, "")
    if code = ""
        code = StringOr(airport.code_icao, StringOr(airport.code, "Unknown"))
    end if
    return code
end function

function HttpRequest(url as string, headers as object) as object
    transfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.RetainBodyOnError(true)
    transfer.SetUrl(url)

    for each name in headers
        transfer.AddHeader(name, headers[name])
    end for

    if not transfer.AsyncGetToString()
        return { code: 0, body: "", failureReason: "The network request could not be started." }
    end if

    event = Wait(30000, port)
    if Type(event) <> "roUrlEvent"
        transfer.AsyncCancel()
        return { code: 0, body: "", failureReason: "The network request timed out." }
    end if

    return {
        code: event.GetResponseCode()
        body: event.GetString()
        failureReason: event.GetFailureReason()
    }
end function

function HttpJsonPost(url as string, headers as object, body as string) as object
    transfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.RetainBodyOnError(true)
    transfer.SetUrl(url)
    transfer.AddHeader("Content-Type", "application/json")
    for each name in headers
        transfer.AddHeader(name, headers[name])
    end for

    if not transfer.AsyncPostFromString(body)
        return { code: 0, body: "", failureReason: "The network request could not be started." }
    end if

    event = Wait(30000, port)
    if Type(event) <> "roUrlEvent"
        transfer.AsyncCancel()
        return { code: 0, body: "", failureReason: "The network request timed out." }
    end if
    return {
        code: event.GetResponseCode()
        body: event.GetString()
        failureReason: event.GetFailureReason()
    }
end function

function AuthHeaders(params as object) as object
    token = StringOr(params.localToken, "")
    headers = {
        "Accept": "application/json"
        "User-Agent": "FlightLane/0.9.5 Roku"
    }
    if token <> ""
        headers.Authorization = "Bearer " + token
    end if
    return headers
end function

function ParseJsonBody(body as string) as dynamic
    if body = ""
        return invalid
    end if
    return ParseJson(body)
end function

function ResponseError(response as object, data as dynamic) as string
    if data <> invalid
        if IsNonEmptyString(data.message)
            return data.message
        end if
        if IsNonEmptyString(data.error)
            return data.error
        end if
        if data.error <> invalid and IsNonEmptyString(data.error.message)
            return data.error.message
        end if
    end if
    if IsNonEmptyString(response.failureReason)
        return response.failureReason
    end if
    if response.code = 429
        return "The flight-data service rate limit was reached."
    end if
    return "The flight-data service returned an unexpected response."
end function

function SuccessResult(operation as string, data as dynamic) as object
    return { operation: operation, ok: true, data: data, code: 200 }
end function

function FailureResult(operation as string, message as string, code as integer) as object
    print "Flight Lane API error ["; operation; "] HTTP "; code; ": "; message
    return { operation: operation, ok: false, errorMessage: message, code: code }
end function
