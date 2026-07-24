sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    memoryState = CreateFlightLaneMemoryMonitor(port)
    screen.Show()
    scene.SignalBeacon("AppLaunchComplete")

    while true
        message = Wait(0, port)
        messageType = Type(message)
        if messageType = "roSGScreenEvent" and message.IsScreenClosed()
            return
        else
            HandleFlightLaneMemoryMessage(message, scene)
        end if
    end while
end sub
