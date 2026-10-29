sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("SpelunkrScene")
    input = CreateObject("roInput")
    input.SetMessagePort(port)
    if args <> invalid then scene.launchArgs = args
    screen.Show()
    while true
        event = Wait(0, port)
        if Type(event) = "roSGScreenEvent"
            if event.IsScreenClosed() then return
        else if Type(event) = "roInputEvent"
            scene.launchArgs = event.GetInfo()
        end if
    end while
end sub
