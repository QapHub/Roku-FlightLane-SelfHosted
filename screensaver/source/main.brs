sub RunScreenSaver()
    RunFlightLaneScene("MainScene", "")
end sub

sub RunScreenSaverSettings()
    RunFlightLaneScene("ScreensaverSettingsScene", "finished")
end sub

sub RunFlightLaneScene(sceneName as string, finishedField as string)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene(sceneName)
    memoryState = CreateFlightLaneMemoryMonitor(port)
    if finishedField <> ""
        scene.ObserveField(finishedField, port)
    end if
    screen.Show()
    scene.SignalBeacon("AppLaunchComplete")

    while true
        message = Wait(0, port)
        messageType = Type(message)
        if messageType = "roSGScreenEvent" and message.IsScreenClosed()
            return
        end if
        if messageType = "roSGNodeEvent" and message.GetField() = finishedField
            return
        end if
        HandleFlightLaneMemoryMessage(message, scene)
    end while
end sub
