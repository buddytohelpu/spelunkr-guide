sub init()
    m.top.backgroundColor = "0x1c0a57ff"
    m.top.setFocus(true)
    m.chrome = m.top.findNode("chrome")
    m.player = m.top.findNode("player")
    m.audio = m.top.findNode("stationAudio")
    m.card = m.top.findNode("stationCard")
    m.channels = []
    m.channelIndex = 0
    m.programIndex = 0
    m.firstRow = 0
    m.mode = "guide"
    m.tunedId = ""
    m.broadcast = invalid
    m.token = 0
    m.clockOffset = 0.0
    m.nextTuneAt = 0.0
    m.retryGuideAt = 0.0
    m.bannerUntil = 0.0
    m.toastUntil = 0.0
    m.guideLoading = false
    m.tuning = false
    m.seekPending = false
    m.lastSyncAt = 0.0
    m.lastMinute = -1
    m.requestSerial = 0
    m.networkTask = CreateObject("roSGNode", "NetworkTask")
    m.networkTask.observeField("guideResult", "onGuide")
    m.networkTask.observeField("tuneResult", "onTune")
    m.networkTask.control = "run"
    m.registry = CreateObject("roRegistrySection", "spelunkr")
    m.savedId = m.registry.Read("channel")
    if m.savedId = "" then m.savedId = "it-came-from"
    drawChrome()
    m.player.observeField("state", "onPlayerState")
    m.top.findNode("tick").observeField("fire", "onTick")
    m.top.findNode("tick").control = "start"
    m.top.findNode("guideRefresh").observeField("fire", "loadGuide")
    m.top.findNode("guideRefresh").control = "start"
    m.top.findNode("cardBrand").font = face(17, true)
    m.top.findNode("cardText").font = face(16)
    m.top.findNode("bannerTitle").font = face(18, true)
    m.top.findNode("bannerHint").font = face(12)
    m.top.findNode("toastText").font = face(14)
    m.top.findNode("helpTitle").font = face(22, true)
    m.top.findNode("helpText").font = face(17)
    m.top.findNode("helpFooter").font = face(15, true)
    m.top.findNode("helpCredit").font = face(11)
    m.top.findNode("helpText").text = "UP / DOWN   Browse channels. In full screen, change channels." + Chr(10) + Chr(10) + "LEFT / RIGHT   See what's coming up." + Chr(10) + Chr(10) + "OK   Watch the selected channel. Press again for the guide." + Chr(10) + Chr(10) + "BACK   Return to the guide. From the guide, exit." + Chr(10) + Chr(10) + "STAR   Show these controls."
    loadGuide()
end sub

function face(size as Integer, bold = false as Boolean) as Object
    font = CreateObject("roSGNode", "Font")
    font.uri = "pkg:/fonts/JetBrainsMono-Regular.ttf"
    if bold then font.uri = "pkg:/fonts/JetBrainsMono-Bold.ttf"
    font.size = size
    return font
end function

function label(parent as Object, x as Integer, y as Integer, width as Integer, height as Integer, text as String, size as Integer, color = "0xffffffff" as String, bold = false as Boolean) as Object
    node = parent.createChild("Label")
    node.translation = [x, y]
    node.width = width
    node.height = height
    node.text = text
    node.font = face(size, bold)
    node.color = color
    node.vertAlign = "center"
    return node
end function

function rectangle(parent as Object, x as Integer, y as Integer, width as Integer, height as Integer, color as String) as Object
    node = parent.createChild("Rectangle")
    node.translation = [x, y]
    node.width = width
    node.height = height
    node.color = color
    return node
end function

function gradientPanel(parent as Object, x as Integer, y as Integer, width as Integer, height as Integer, asset as String) as Object
    node = parent.createChild("Poster")
    node.translation = [x, y]
    node.width = width
    node.height = height
    node.uri = "pkg:/images/" + asset
    node.loadDisplayMode = "scaleToFill"
    return node
end function

sub drawChrome()
    rectangle(m.chrome, 48, 24, 1184, 48, "0x1c0a57ff")
    gradientPanel(m.chrome, 48, 24, 500, 48, "header-band.png")
    rectangle(m.chrome, 40, 90, 1200, 248, "0x2652b2ff")
    rectangle(m.chrome, 42, 92, 1196, 244, "0x21285aff")
    label(m.chrome, 58, 25, 255, 39, "SPELUNKR.", 33, "0xffff00ff", true)
    label(m.chrome, 305, 30, 450, 30, "CABLE TV, BUT WEIRDER.", 12, "0xffffffff")
    label(m.chrome, 930, 30, 145, 30, "ON THE AIR", 12, "0x8ffdfaff")
    m.clockLabel = label(m.chrome, 1095, 28, 140, 32, "", 19)
    rectangle(m.chrome, 48, 78, 1184, 1, "0x2652b2ff")
    m.channelLabel = label(m.chrome, 48, 98, 810, 26, "ADJUSTING THE ANTENNA", 14, "0xffff00ff", true)
    m.titleLabel = label(m.chrome, 48, 134, 815, 75, "Something good is on somewhere.", 30, "0xffff00ff", true)
    m.titleLabel.wrap = true
    m.titleLabel.numLines = 2
    m.metaLabel = label(m.chrome, 48, 215, 810, 24, "LIVE NOW  /  FROM THE ARCHIVE", 12, "0xd6dcffff")
    m.descriptionLabel = label(m.chrome, 48, 247, 810, 47, "Forgotten films. Found footage. Beautifully strange television.", 13, "0xd6dcffff")
    m.descriptionLabel.wrap = true
    m.descriptionLabel.numLines = 2
    gradientPanel(m.chrome, 48, 306, 193, 29, "button-fill.png")
    label(m.chrome, 59, 306, 174, 29, "OK  WATCH CHANNEL", 12, "0xffff00ff", true)
    m.remainingLabel = label(m.chrome, 259, 306, 560, 29, "", 12, "0xd6dcffff")
    m.previewCaption = label(m.chrome, 900, 292, 335, 24, "YOUR WINDOW INTO THE ARCHIVE", 9, "0xd6dcffff")
    rectangle(m.chrome, 48, 354, 1184, 37, "0x1c0a57ff")
    label(m.chrome, 62, 354, 350, 37, "THE CHANNEL GUIDE", 14, "0xffff00ff", true)
    m.countLabel = label(m.chrome, 390, 354, 570, 37, "FIND YOUR FREQUENCY", 10, "0xd6dcffff")
    rectangle(m.chrome, 48, 391, 1184, 29, "0x200057ff")
    label(m.chrome, 62, 391, 205, 29, "CHANNEL", 11, "0xffff00ff")
    m.timeLabels = []
    for i = 0 to 3
        m.timeLabels.push(label(m.chrome, 284 + i * 237, 391, 237, 29, "", 11, "0xffff00ff"))
    end for
    m.rows = m.chrome.createChild("Group")
    rectangle(m.chrome, 48, 630, 1184, 23, "0x1c0a57ff")
    m.positionLabel = label(m.chrome, 62, 630, 200, 23, "-- / --", 10, "0xd6dcffff")
    label(m.chrome, 359, 630, 700, 23, "SAME CHANNEL. SAME MOMENT. EVERYONE.", 10, "0xd6dcffff")
    rectangle(m.chrome, 48, 655, 1184, 50, "0x233270ff")
    label(m.chrome, 60, 657, 970, 21, "UP / DOWN  CHANNELS     LEFT / RIGHT  PROGRAMS     OK  WATCH     BACK  GUIDE", 11, "0xd6dcffff")
    label(m.chrome, 1080, 657, 145, 21, "* REMOTE HELP", 11, "0xd6dcffff")
    credit = label(m.chrome, 60, 683, 1160, 20, "Original project by Spelunkr.tv  |  Video: Internet Archive", 11, "0xffff00ff")
    credit.horizAlign = "center"
    m.statusLabel = label(m.rows, 80, 495, 1100, 45, "SEARCHING FOR A SIGNAL...", 18, "0xffff00ff")
end sub

function nowMs() as Double
    return epochMs() + m.clockOffset
end function

sub loadGuide()
    if m.guideLoading then return
    m.guideLoading = true
    m.requestSerial++
    m.networkTask.request = { serial: m.requestSerial, action: "guide", channelId: m.savedId, progressive: m.channels.count() = 0 }
end sub

sub onGuide(event as Object)
    result = event.getData()
    m.guideLoading = not result.complete
    if not result.ok
        m.retryGuideAt = nowMs() + 15000
        if m.channels.count() = 0
            showSetupError(result.error)
        else
            m.countLabel.text = "CACHED GUIDE - RETRYING SIGNAL"
        end if
        return
    end if
    data = result.data
    m.clockOffset = data.serverTime - epochMs()
    selectedId = m.savedId
    selectedKey = ""
    if m.channels.count() > 0
        previous = m.channels[m.channelIndex]
        selectedId = previous.id
        if previous.programs.count() > m.programIndex then selectedKey = previous.programs[m.programIndex].key
    end if
    m.channels = data.channels
    m.guideStart = data.startMs
    m.guideEnd = data.endMs
    m.retryGuideAt = 0
    m.channelIndex = 0
    for i = 0 to m.channels.count() - 1
        if m.channels[i].id = selectedId then m.channelIndex = i
    end for
    selectNow()
    if m.channels.count() > 0
        programs = m.channels[m.channelIndex].programs
        for i = 0 to programs.count() - 1
            if programs[i].key = selectedKey then m.programIndex = i
        end for
    end if
    m.countLabel.text = m.channels.count().ToStr() + " CHANNELS / ALWAYS SOMETHING ON"
    if not result.complete then m.countLabel.text = "TUNING THE DIAL / " + result.loaded.ToStr() + " OF " + m.channels.count().ToStr() + " CHANNELS"
    if data.source <> "live" then m.countLabel.text = UCase(data.source) + " SCHEDULE / " + m.channels.count().ToStr() + " CHANNELS"
    for i = 0 to 3
        m.timeLabels[i].text = clockText(m.guideStart + i * 1800000)
    end for
    drawRows()
    updateDetails()
    if m.tunedId = "" and m.channels.count() > 0
        if m.channels[m.channelIndex].programs.count() > 0 then tuneSelected()
    end if
end sub

sub showSetupError(message as String)
    m.titleLabel.text = "The antenna needs a moment."
    m.descriptionLabel.text = message
    m.metaLabel.text = "SPELUNKR.TV / CHECK YOUR INTERNET CONNECTION"
    m.rows.removeChildrenIndex(m.rows.getChildCount(), 0)
    label(m.rows, 80, 462, 1100, 40, "WAITING FOR SPELUNKR'S BROADCAST", 20, "0xffff00ff", true)
    label(m.rows, 80, 510, 1100, 40, "PRESS OK TO RETRY  /  * FOR REMOTE HELP", 14, "0xd6dcffff")
end sub

sub selectNow()
    m.programIndex = 0
    if m.channels.count() = 0 then return
    programs = m.channels[m.channelIndex].programs
    for i = 0 to programs.count() - 1
        if programs[i].startMs <= nowMs() and programs[i].endMs > nowMs() then m.programIndex = i
    end for
end sub

sub drawRows()
    m.rows.removeChildrenIndex(m.rows.getChildCount(), 0)
    if m.channels.count() = 0 then return
    if m.channelIndex < m.firstRow then m.firstRow = m.channelIndex
    if m.channelIndex >= m.firstRow + 5 then m.firstRow = m.channelIndex - 4
    m.firstRow = maximum(0, minimum(m.firstRow, m.channels.count() - 5))
    for slot = 0 to 4
        ci = m.firstRow + slot
        if ci < m.channels.count()
            channel = m.channels[ci]
            y = 420 + slot * 42
            selected = ci = m.channelIndex
            bg = "0x001040ff"
            numberColor = "0xffff00ff"
            if selected
                bg = "0x974717ff"
                numberColor = "0xffff00ff"
            end if
            rectangle(m.rows, 48, y, 236, 41, bg)
            if selected
                gradientPanel(m.rows, 48, y, 236, 41, "button-fill.png")
                rectangle(m.rows, 48, y, 3, 41, "0xffff00ff")
            end if
            label(m.rows, 63, y + 2, 55, 40, dialText(channel.number), 22, numberColor)
            label(m.rows, 118, y + 3, 159, 23, channel.name, 11, "0xffffffff", true)
            subtext = "24/7 BROADCAST"
            subColor = "0xa8a8ffff"
            if channel.id = m.tunedId
                subtext = "ON YOUR TELEVISION"
                subColor = "0x8ffdfaff"
            end if
            label(m.rows, 118, y + 27, 160, 13, subtext, 8, subColor)
            rectangle(m.rows, 284, y, 948, 41, "0x001040ff")
            for pi = 0 to channel.programs.count() - 1
                program = channel.programs[pi]
                ' JSON timestamps are LongIntegers. Promote before division to keep fractional positions.
                startFraction = 1.0# * (program.startMs - m.guideStart) / (m.guideEnd - m.guideStart)
                endFraction = 1.0# * (program.endMs - m.guideStart) / (m.guideEnd - m.guideStart)
                x = 284 + Int(maximum(0, startFraction) * 948)
                rightEdge = 284 + Int(minimum(1, endFraction) * 948)
                width = rightEdge - x - 1
                if width > 0
                    cellColor = "0x001040ff"
                    titleColor = "0xffffffff"
                    subColor = "0xd6dcffff"
                    if pi mod 2 = 1 then cellColor = "0x102080ff"
                    if selected and pi = m.programIndex
                        rectangle(m.rows, x, y, width, 41, "0xffff00ff")
                        cellColor = "0x2a26c8ff"
                        titleColor = "0xffffffff"
                        subColor = "0xe6e8ffff"
                        rectangle(m.rows, x + 2, y + 2, maximum(1, width - 4), 37, cellColor)
                    else
                        rectangle(m.rows, x, y, width, 41, cellColor)
                    end if
                    if width > 26
                        label(m.rows, x + 10, y + 4, width - 18, 23, program.title, 12, titleColor, selected and pi = m.programIndex)
                        meta = clockText(program.startMs)
                        if program.year <> "" then meta = program.year + " / " + meta
                        label(m.rows, x + 10, y + 27, width - 18, 12, meta, 8, subColor)
                    end if
                end if
            end for
        end if
    end for
    m.positionLabel.text = dialText(m.channelIndex + 1) + " / " + m.channels.count().ToStr()
end sub

sub updateDetails()
    if m.channels.count() = 0 then return
    channel = m.channels[m.channelIndex]
    m.channelLabel.text = "CH " + dialText(channel.number) + "  /  " + channel.name
    m.descriptionLabel.text = channel.description
    if channel.programs.count() = 0
        m.titleLabel.text = "Adjusting the antenna..."
        m.metaLabel.text = "SIGNAL UNAVAILABLE"
        m.remainingLabel.text = "TRY ANOTHER CHANNEL"
        return
    end if
    m.programIndex = minimum(m.programIndex, channel.programs.count() - 1)
    program = channel.programs[m.programIndex]
    m.titleLabel.text = program.title
    status = "LIVE NOW"
    m.remainingLabel.text = maximum(1, Int((program.endMs - nowMs()) / 60000)).ToStr() + " MIN REMAINING"
    if program.startMs > nowMs()
        status = "UP NEXT"
        m.remainingLabel.text = "STARTS AT " + clockText(program.startMs)
    else if program.endMs < nowMs()
        status = "EARLIER"
        m.remainingLabel.text = "TUNE IN TO WATCH LIVE"
    end if
    year = "FROM THE ARCHIVE"
    if program.year <> "" then year = program.year
    m.metaLabel.text = status + "  /  " + year + "  /  " + clockText(program.startMs) + " - " + clockText(program.endMs)
end sub

sub tuneSelected()
    if m.channels.count() = 0 then return
    channel = m.channels[m.channelIndex]
    if channel.programs.count() = 0
        showToast("This channel's signal is unavailable. Try another channel.")
        return
    end if
    m.tunedId = channel.id
    m.registry.Write("channel", channel.id)
    m.registry.Flush()
    requestTune()
end sub

sub requestTune()
    if m.tunedId = "" then return
    m.token++
    m.tuning = true
    m.player.control = "stop"
    m.player.visible = false
    m.audio.control = "stop"
    m.card.visible = true
    m.top.findNode("cardText").text = "TUNING IN..."
    m.requestSerial++
    m.networkTask.request = { serial: m.requestSerial, action: "tune", channelId: m.tunedId, token: m.token }
end sub

sub onTune(event as Object)
    result = event.getData()
    if result.token <> m.token then return
    m.tuning = false
    if not result.ok
        m.top.findNode("cardText").text = "THE SIGNAL WANDERED OFF." + Chr(10) + "TRYING AGAIN..."
        m.nextTuneAt = nowMs() + 10000
        return
    end if
    data = result.data
    m.clockOffset = data.serverTime - epochMs()
    m.broadcast = data
    m.nextTuneAt = data.endMs
    if data.endMs <= nowMs()
        requestTune()
        return
    end if
    m.previewCaption.text = "CH " + dialText(data.channel.number) + " / " + data.channel.name
    if data.url <> ""
        content = CreateObject("roSGNode", "ContentNode")
        content.url = data.url
        content.streamFormat = "mp4"
        content.title = data.title
        content.playStart = Int(data.seek)
        m.player.content = content
        m.seekPending = true
        m.player.control = "play"
    else
        updateStationCard()
        if data.audioUrl <> ""
            content = CreateObject("roSGNode", "ContentNode")
            content.url = data.audioUrl
            content.streamFormat = "mp3"
            m.audio.content = content
            m.audio.control = "play"
            m.audio.seek = Int(data.audioSeek)
        end if
    end if
    drawRows()
    if m.mode = "watch" then showBanner()
    m.top.setFocus(true)
end sub

sub onPlayerState()
    status = m.player.state
    if status = "playing"
        m.player.visible = true
        m.card.visible = false
        if m.seekPending and m.broadcast <> invalid
            m.seekPending = false
            m.player.seek = Int(m.broadcast.seek + (nowMs() - m.broadcast.serverTime) / 1000)
        end if
    else if status = "error"
        m.player.visible = false
        m.card.visible = true
        m.top.findNode("cardText").text = "THIS TAPE IS HAVING A MOMENT." + Chr(10) + "TRYING AGAIN..."
        m.nextTuneAt = minimum(m.nextTuneAt, nowMs() + 12000)
    else if status = "finished"
        m.nextTuneAt = minimum(m.nextTuneAt, nowMs() + 1000)
    end if
end sub

sub updateStationCard()
    if m.broadcast = invalid then return
    if m.broadcast.url <> "" then return
    text = "YOU ARE WATCHING" + Chr(10) + m.broadcast.channel.name
    offset = nowMs() - m.broadcast.startMs
    for each card in m.broadcast.cards
        if offset >= card.start and offset < card.end then text = card.text
    end for
    if m.broadcast.message <> invalid then text = m.broadcast.message
    m.top.findNode("cardText").text = text
end sub

sub setMode(mode as String)
    m.mode = mode
    m.chrome.visible = mode = "guide"
    if mode = "watch"
        m.player.translation = [0, 0]
        m.player.width = 1280
        m.player.height = 720
        m.card.translation = [0, 0]
        m.top.findNode("cardBackground").width = 1280
        m.top.findNode("cardBackground").height = 720
        m.top.findNode("cardBrand").translation = [100, 185]
        m.top.findNode("cardBrand").width = 1080
        m.top.findNode("cardBrand").font = face(30, true)
        m.top.findNode("cardText").translation = [180, 260]
        m.top.findNode("cardText").width = 920
        m.top.findNode("cardText").height = 230
        m.top.findNode("cardText").font = face(30)
        showBanner()
    else
        m.player.translation = [900, 100]
        m.player.width = 332
        m.player.height = 187
        m.card.translation = [900, 100]
        m.top.findNode("cardBackground").width = 332
        m.top.findNode("cardBackground").height = 187
        m.top.findNode("cardBrand").translation = [16, 18]
        m.top.findNode("cardBrand").width = 300
        m.top.findNode("cardBrand").font = face(17, true)
        m.top.findNode("cardText").translation = [20, 55]
        m.top.findNode("cardText").width = 292
        m.top.findNode("cardText").height = 98
        m.top.findNode("cardText").font = face(16)
        m.top.findNode("banner").visible = false
        selectTunedChannel()
        drawRows()
        updateDetails()
    end if
    m.top.setFocus(true)
end sub

sub selectTunedChannel()
    for i = 0 to m.channels.count() - 1
        if m.channels[i].id = m.tunedId then m.channelIndex = i
    end for
    selectNow()
end sub

sub showBanner()
    if m.broadcast = invalid then return
    m.top.findNode("bannerTitle").text = "CH " + dialText(m.broadcast.channel.number) + " / " + m.broadcast.channel.name + " - " + m.broadcast.title
    m.top.findNode("banner").visible = true
    m.bannerUntil = nowMs() + 4500
end sub

sub showToast(text as String)
    m.top.findNode("toastText").text = text
    m.top.findNode("toast").visible = true
    m.toastUntil = nowMs() + 3500
end sub

sub onTick()
    current = nowMs()
    m.clockLabel.text = clockText(current)
    if current > m.bannerUntil then m.top.findNode("banner").visible = false
    if current > m.toastUntil then m.top.findNode("toast").visible = false
    if not m.tuning and m.nextTuneAt > 0 and current >= m.nextTuneAt then requestTune()
    if not m.guideLoading and m.retryGuideAt > 0 and current >= m.retryGuideAt then loadGuide()
    updateStationCard()
    minute = Int(current / 60000)
    if minute <> m.lastMinute
        m.lastMinute = minute
        updateDetails()
    end if
    if m.broadcast <> invalid and m.player.state = "playing" and current - m.lastSyncAt > 8000
        m.lastSyncAt = current
        target = m.broadcast.seek + (current - m.broadcast.serverTime) / 1000
        if Abs(m.player.position - target) > 6 then m.player.seek = Int(target)
    end if
end sub

sub onLaunchArgs()
    args = m.top.launchArgs
    if args = invalid then return
    if args.contentId <> invalid
        m.savedId = args.contentId
        for i = 0 to m.channels.count() - 1
            if m.channels[i].id = m.savedId
                m.channelIndex = i
                selectNow()
                tuneSelected()
                setMode("watch")
                return
            end if
        end for
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.top.findNode("help").visible
        if key = "OK" or key = "back" or key = "options" then m.top.findNode("help").visible = false
        return true
    end if
    if key = "options"
        m.top.findNode("help").visible = true
        return true
    end if
    if key = "back"
        if m.mode = "watch"
            setMode("guide")
            return true
        end if
        return false
    end if
    if key = "OK"
        if m.channels.count() = 0
            loadGuide()
        else if m.mode = "watch"
            setMode("guide")
        else
            channel = m.channels[m.channelIndex]
            if channel.programs.count() > 0
                if channel.programs[m.programIndex].startMs > nowMs() then showToast("That program airs later. Tuning to what's live now.")
                if m.tunedId <> channel.id or m.player.state = "error" then tuneSelected()
                setMode("watch")
            else
                showToast("This channel's signal is unavailable. Try another channel.")
            end if
        end if
        return true
    end if
    if m.channels.count() = 0 then return false
    if key = "up" or key = "down"
        if m.mode = "watch" then selectTunedChannel()
        delta = 1
        if key = "up" then delta = -1
        m.channelIndex = (m.channelIndex + delta + m.channels.count()) mod m.channels.count()
        selectNow()
        if m.mode = "watch" then tuneSelected()
        drawRows()
        updateDetails()
        return true
    end if
    if key = "left" or key = "right"
        if m.mode = "guide"
            delta = 1
            if key = "left" then delta = -1
            m.programIndex = maximum(0, minimum(m.channels[m.channelIndex].programs.count() - 1, m.programIndex + delta))
            drawRows()
            updateDetails()
        end if
        return true
    end if
    if key = "play" or key = "rewind" or key = "fastforward" or key = "replay"
        showToast("This channel is live. Everyone is watching the same moment.")
        return true
    end if
    return false
end function
