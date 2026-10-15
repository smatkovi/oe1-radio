import QtQuick 1.1
import com.nokia.meego 1.0
import QtMultimediaKit 1.1

PageStackWindow {
    id: appWindow
    initialPage: mainPage
    showStatusBar: true
    showToolBar: true
    
    property string quality: "low"
    property string showTitle: "Ö1"
    property string showSubtitle: ""
    property string showStart: ""
    property string showEnd: ""
    property int sleepTimerRemaining: 0
    property bool sleepTimerActive: false
    property string currentOnDemandUrl: ""
    property bool playingOnDemand: false
    property double liveStartTime: 0  // Timestamp wenn Livestream gestartet
    property int currentOnDemandId: 0  // ID der aktuell spielenden OnDemand-Sendung
    
    // Stream URLs
    property string streamLow: "http://ors-sn10.ors-shoutcast.at/oe1-q1a"
    property string streamMedium: "http://ors-sn10.ors-shoutcast.at/oe1-q2a"
    property string streamHigh: "https://orf-live-oe1.mdn.ors.at/out/u/oe1/qxa/manifest.m3u8"
    
    function getStreamUrl() {
        if (quality === "medium") return streamMedium
        if (quality === "high") return streamHigh
        return streamLow
    }
    
    function formatSleepTime(seconds) {
        var m = Math.floor(seconds / 60)
        var s = seconds % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    
    Component.onCompleted: {
        theme.inverted = true
        oe1.refreshCurrentShow()
        oe1.refreshSchedule()
    }
    
    // Audio Player
    Audio {
        id: audioPlayer
        source: getStreamUrl()
        volume: volumeSlider.value / 100
        
        onStatusChanged: {
            console.log("[QML] Audio status changed to: " + status)
            if (status === Audio.Buffering) {
                console.log("[QML] Status: Buffering")
                statusText.text = "Puffern..."
            } else if (status === Audio.Stalled) {
                console.log("[QML] Status: Stalled")
                statusText.text = "Verbindung..."
            } else if (status === Audio.EndOfMedia) {
                console.log("[QML] Status: EndOfMedia")
                statusText.text = "Stream beendet"
            } else if (status === Audio.InvalidMedia) {
                console.log("[QML] Status: InvalidMedia")
                statusText.text = "Fehler"
            } else if (status === Audio.Loaded) {
                console.log("[QML] Status: Loaded")
                statusText.text = playingOnDemand ? "On-Demand" : "Bereit"
            }
            console.log("[QML] Status handler done")
        }
        
        onError: {
            console.log("[QML] Audio error: " + errorString)
            statusText.text = "Fehler"
        }
    }
    
    // Timer für verzögertes URL-Setzen (verhindert UI-Blockade)
    Timer {
        id: playUrlTimer
        interval: 50
        repeat: false
        property string targetUrl: ""
        onTriggered: {
            audioPlayer.source = targetUrl
            audioPlayer.play()
            statusText.text = "On-Demand"
            heartbeatTimer.count = 0
            heartbeatTimer.start()
        }
    }
    
    // Heartbeat Timer - zeigt ob Event-Loop läuft
    Timer {
        id: heartbeatTimer
        interval: 500
        repeat: true
        property int count: 0
        onTriggered: {
            count++
            if (count <= 3) console.log("[QML] Heartbeat " + count)
            if (count > 10) stop()
        }
    }
    
    // Backend Connections
    Connections {
        target: oe1
        
        onCurrentShowChanged: {
            // Nur updaten wenn nicht OnDemand abspielt
            if (!playingOnDemand) {
                try {
                    var show = JSON.parse(oe1.showJson)
                    appWindow.showTitle = show.title || "Ö1"
                    appWindow.showSubtitle = show.subtitle || ""
                    appWindow.showStart = show.startTime || ""
                    appWindow.showEnd = show.endTime || ""
                } catch(e) {
                    appWindow.showTitle = "Ö1"
                }
            }
        }
        
        onScheduleChanged: {
            try {
                var items = JSON.parse(oe1.scheduleJson)
                scheduleModel.clear()
                for (var i = 0; i < items.length; i++) {
                    scheduleModel.append(items[i])
                }
            } catch(e) {}
        }
        
        onOnDemandDaysChanged: {
            try {
                var items = JSON.parse(oe1.daysJson)
                daysModel.clear()
                for (var i = 0; i < items.length; i++) {
                    daysModel.append(items[i])
                }
            } catch(e) {}
        }
        
        onOnDemandBroadcastsChanged: {
            try {
                var items = JSON.parse(oe1.broadcastsJson)
                onDemandModel.clear()
                for (var i = 0; i < items.length; i++) {
                    onDemandModel.append(items[i])
                }
                onDemandBusy.running = false
            } catch(e) {
                onDemandBusy.running = false
            }
        }
        
        onPodcastsChanged: {
            try {
                var items = JSON.parse(oe1.podcastsJson)
                podcastsModel.clear()
                for (var i = 0; i < items.length; i++) {
                    podcastsModel.append(items[i])
                }
                podcastsBusy.running = false
            } catch(e) {
                podcastsBusy.running = false
            }
        }
        
        onPodcastEpisodesChanged: {
            try {
                var items = JSON.parse(oe1.episodesJson)
                episodesModel.clear()
                for (var i = 0; i < items.length; i++) {
                    episodesModel.append(items[i])
                }
                episodesBusy.running = false
            } catch(e) {
                episodesBusy.running = false
            }
        }
        
        onSearchResultsChanged: {
            try {
                var items = JSON.parse(oe1.resultsJson)
                searchModel.clear()
                for (var i = 0; i < items.length; i++) {
                    searchModel.append(items[i])
                }
                searchBusy.running = false
            } catch(e) {
                searchBusy.running = false
            }
        }
        
        onPlayUrlChanged: {
            console.log("[QML] Playing: " + oe1.url.substring(0, 60))
            currentOnDemandUrl = oe1.url
            playingOnDemand = true
            audioPlayer.stop()
            playUrlTimer.targetUrl = oe1.url
            playUrlTimer.start()
        }
        
        onSleepTimerTick: {
            sleepTimerRemaining = oe1.remaining
        }
        
        onSleepTimerFinished: {
            sleepTimerActive = false
            sleepTimerRemaining = 0
            audioPlayer.stop()
            statusText.text = "Sleep Timer beendet"
        }
        
        onErrorOccurred: {
            statusText.text = oe1.message
        }
    }
    
    // Models
    ListModel { id: scheduleModel }
    ListModel { id: daysModel }
    ListModel { id: onDemandModel }
    ListModel { id: podcastsModel }
    ListModel { id: episodesModel }
    ListModel { id: searchModel }
    
    // Main Page
    Page {
        id: mainPage
        orientationLock: PageOrientation.LockPortrait
        
        tools: ToolBarLayout {
            ToolIcon {
                iconId: "toolbar-view-menu"
                onClicked: mainMenu.open()
            }
            ToolIcon {
                iconId: "toolbar-refresh"
                onClicked: {
                    oe1.refreshCurrentShow()
                    oe1.refreshSchedule()
                }
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }
        
        Flickable {
            anchors.fill: parent
            contentHeight: mainColumn.height + 40
            clip: true
            
            Column {
                id: mainColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                }
                spacing: 16
                
                // Header with Sleep Timer indicator
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    
                    Label {
                        text: "Ö1"
                        font.pixelSize: 48
                        font.bold: true
                        color: "white"
                    }
                    
                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: audioPlayer.playing ? "#c41e3a" : "#666"
                        anchors.verticalCenter: parent.verticalCenter
                        
                        SequentialAnimation on opacity {
                            running: audioPlayer.status === Audio.Buffering
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 500 }
                            NumberAnimation { to: 1.0; duration: 500 }
                        }
                    }
                    
                    // Sleep timer indicator
                    Rectangle {
                        visible: sleepTimerActive
                        width: sleepLabel.width + 16
                        height: 24
                        radius: 12
                        color: "#444"
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Label {
                            id: sleepLabel
                            anchors.centerIn: parent
                            text: "⏱ " + formatSleepTime(sleepTimerRemaining)
                            font.pixelSize: 12
                            color: "#ffa500"
                        }
                    }
                }
                
                // Quality indicator
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: playingOnDemand ? "On-Demand" :
                          quality === "low" ? "2G/EDGE (48 kbps)" :
                          quality === "medium" ? "3G (128 kbps)" : "WLAN (HLS)"
                    font.pixelSize: 14
                    color: playingOnDemand ? "#4da6ff" : "#888"
                }
                
                // Current Show
                Rectangle {
                    width: parent.width
                    height: showCol.height + 32
                    color: "#333"
                    radius: 12
                    
                    Column {
                        id: showCol
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: 16
                        }
                        spacing: 8
                        
                        Label {
                            text: playingOnDemand ? "ON-DEMAND" : "JETZT"
                            font.pixelSize: 12
                            font.bold: true
                            color: playingOnDemand ? "#4da6ff" : "#c41e3a"
                        }
                        
                        Label {
                            width: parent.width
                            text: showTitle
                            font.pixelSize: 24
                            font.bold: true
                            color: "white"
                            wrapMode: Text.WordWrap
                        }
                        
                        Label {
                            width: parent.width
                            text: showSubtitle
                            font.pixelSize: 16
                            color: "#aaa"
                            wrapMode: Text.WordWrap
                            visible: showSubtitle !== ""
                        }
                        
                        Label {
                            text: showStart + " - " + showEnd
                            font.pixelSize: 14
                            color: "#666"
                            visible: showStart !== "" && !playingOnDemand
                        }
                        
                        // Info Button für aktuelle Sendung (Live oder OnDemand)
                        Rectangle {
                            width: 60
                            height: 24
                            radius: 12
                            color: "#444"
                            visible: playingOnDemand ? (currentOnDemandId > 0) : (oe1.getCurrentBroadcastId() > 0)
                            
                            Label {
                                anchors.centerIn: parent
                                text: "ⓘ Info"
                                font.pixelSize: 11
                                color: "#aaa"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var id = playingOnDemand ? currentOnDemandId : oe1.getCurrentBroadcastId()
                                    if (id > 0) {
                                        broadcastInfoSheet.broadcastId = id
                                        oe1.loadBroadcastInfo(id)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Play Button Container
                Item {
                    width: parent.width
                    height: 100
                    
                    Rectangle {
                        anchors.centerIn: parent
                        width: 100
                        height: 100
                        radius: 50
                        color: audioPlayer.playing ? "#c41e3a" : "#444"
                        
                        Label {
                            anchors.centerIn: parent
                            text: audioPlayer.playing ? "■" : "▶"
                            font.pixelSize: 40
                            font.bold: true
                            color: "white"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (audioPlayer.playing) {
                                    audioPlayer.stop()
                                    statusText.text = "Gestoppt"
                                    playingOnDemand = false
                                    liveStartTime = 0
                                    currentOnDemandId = 0
                                } else {
                                    playingOnDemand = false
                                    currentOnDemandId = 0
                                    liveStartTime = Date.now()
                                    oe1.startLiveProxy(getStreamUrl())
                                }
                            }
                        }
                        
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
                
                // Status
                Label {
                    id: statusText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: audioPlayer.playing ? (playingOnDemand ? "On-Demand" : "Live") : "Gestoppt"
                    font.pixelSize: 16
                    color: "#888"
                }
                
                // Timeshift Button - zeige wenn Live und Sendung bekannt
                Button {
                    text: "⏮ Von Anfang"
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !playingOnDemand && oe1.getCurrentBroadcastId() > 0
                    onClicked: {
                        playingOnDemand = true
                        oe1.startTimeshift()
                    }
                }
                
                // Seek Slider für OnDemand/Podcasts UND Livestream (Timeshift)
                Column {
                    visible: audioPlayer.playing
                    width: parent.width
                    spacing: 4
                    
                    // Effektive Duration: OnDemand berechnet, Live = Zeit seit Start
                    property int effectiveDuration: playingOnDemand ? 
                        (audioPlayer.duration > 0 ? audioPlayer.duration : oe1.streamDuration) :
                        (liveStartTime > 0 ? liveDurationMs : 0)
                    
                    property int liveDurationMs: 0
                    
                    // Timer um Live-Duration zu aktualisieren
                    Timer {
                        running: !playingOnDemand && liveStartTime > 0 && audioPlayer.playing
                        interval: 1000
                        repeat: true
                        onTriggered: parent.liveDurationMs = Math.floor(Date.now() - liveStartTime)
                    }
                    
                    // Zeige Slider wenn Duration bekannt
                    Row {
                        visible: parent.effectiveDuration > 1000
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        
                        // Position-Wert wird nur alle 500ms aktualisiert um CPU zu sparen
                        property int displayPosition: 0
                        Timer {
                            running: audioPlayer.playing
                            interval: 500
                            repeat: true
                            onTriggered: parent.displayPosition = audioPlayer.position
                        }
                        
                        Label {
                            text: formatDuration(parent.displayPosition)
                            font.pixelSize: 13
                            color: "#888"
                            width: 40
                            horizontalAlignment: Text.AlignRight
                        }
                        
                        Slider {
                            id: seekSlider
                            width: 340
                            minimumValue: 0
                            maximumValue: parent.parent.effectiveDuration > 0 ? parent.parent.effectiveDuration : 1
                            value: seekSliderDragging ? seekSlider.value : parent.displayPosition
                            stepSize: 1000
                            
                            property bool seekSliderDragging: false
                            
                            onPressedChanged: {
                                if (pressed) {
                                    seekSliderDragging = true
                                } else {
                                    // Seek ausführen
                                    console.log("Seeking to: " + value + " ms")
                                    audioPlayer.position = value
                                    seekSliderDragging = false
                                }
                            }
                        }
                        
                        Label {
                            text: formatDuration(parent.parent.effectiveDuration)
                            font.pixelSize: 13
                            color: playingOnDemand ? "#888" : "#4da6ff"
                            width: 40
                        }
                    }
                    
                    // Live-Hinweis
                    Label {
                        visible: !playingOnDemand && liveStartTime > 0 && parent.effectiveDuration > 1000
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "LIVE Timeshift"
                        font.pixelSize: 11
                        color: "#4da6ff"
                    }
                    
                    // Lade-Anzeige wenn keine Duration
                    Label {
                        visible: playingOnDemand && parent.effectiveDuration <= 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Lade..."
                        font.pixelSize: 12
                        color: "#666"
                    }
                }
                
                // Volume
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16
                    
                    Label {
                        text: ""
                        font.pixelSize: 24
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Slider {
                        id: volumeSlider
                        width: 200
                        minimumValue: 0
                        maximumValue: 100
                        value: 80
                        stepSize: 5
                    }
                    
                    Label {
                        text: "Vol"
                        font.pixelSize: 24
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                // Feature Buttons
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    
                    Button {
                        text: "7 Tage"
                        width: 90
                        onClicked: {
                            oe1.loadOnDemandDays()
                            pageStack.push(onDemandPage)
                        }
                    }
                    
                    Button {
                        text: "Podcasts"
                        width: 90
                        onClicked: {
                            podcastsBusy.running = true
                            oe1.loadPodcasts()
                            pageStack.push(podcastsPage)
                        }
                    }
                    
                    Button {
                        text: "Suche"
                        width: 90
                        onClicked: pageStack.push(searchPage)
                    }
                }
                
                // Separator
                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#444"
                }
                
                // Schedule Header
                Label {
                    text: "Programm heute"
                    font.pixelSize: 20
                    font.bold: true
                    color: "white"
                }
                
                // Schedule List
                Column {
                    width: parent.width
                    spacing: 8
                    
                    Repeater {
                        model: Math.min(5, scheduleModel.count)
                        
                        Rectangle {
                            width: mainColumn.width
                            height: 56
                            color: scheduleModel.get(index).isCurrent ? "#442222" :
                                   scheduleModel.get(index).isPast ? "#222" : "#333"
                            radius: 8
                            opacity: scheduleModel.get(index).isPast ? 0.6 : 1.0
                            
                            Row {
                                anchors {
                                    fill: parent
                                    margins: 12
                                }
                                spacing: 12
                                
                                Label {
                                    text: scheduleModel.get(index).time || ""
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: scheduleModel.get(index).isCurrent ? "#ff6666" : "#c41e3a"
                                    width: 50
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                
                                Label {
                                    text: scheduleModel.get(index).title
                                    font.pixelSize: 16
                                    color: "white"
                                    elide: Text.ElideRight
                                    width: parent.width - 70
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var item = scheduleModel.get(index)
                                    if (item.id > 0) {
                                        broadcastInfoSheet.broadcastId = item.id
                                        oe1.loadBroadcastInfo(item.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // 7 Tage Page
    Page {
        id: onDemandPage
        orientationLock: PageOrientation.LockPortrait
        
        tools: ToolBarLayout {
            ToolIcon {
                iconId: "toolbar-back"
                onClicked: pageStack.pop()
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            // Header
            Rectangle {
                width: parent.width
                height: 60
                color: "#222"
                
                Label {
                    anchors.centerIn: parent
                    text: "7 Tage Nachhören"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }
            }
            
            // Days tabs
            ListView {
                id: daysListView
                width: parent.width
                height: 60
                orientation: ListView.Horizontal
                model: daysModel
                clip: true
                
                delegate: Rectangle {
                    width: 120
                    height: 60
                    color: ListView.isCurrentItem ? "#c41e3a" : "#333"
                    
                    Column {
                        anchors.centerIn: parent
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: model.weekday
                            font.pixelSize: 14
                            font.bold: true
                            color: "white"
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: model.displayDate
                            font.pixelSize: 12
                            color: "#ccc"
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            daysListView.currentIndex = index
                            onDemandBusy.running = true
                            onDemandModel.clear()
                            oe1.loadOnDemandBroadcasts(model.date)
                        }
                    }
                }
            }
            
            // Loading indicator
            BusyIndicator {
                id: onDemandBusy
                anchors.horizontalCenter: parent.horizontalCenter
                running: false
                visible: running
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
            
            // Broadcasts list
            ListView {
                width: parent.width
                height: parent.height - 120
                model: onDemandModel
                clip: true
                
                delegate: Rectangle {
                    width: parent.width
                    height: 80
                    color: index % 2 === 0 ? "#252525" : "#2a2a2a"
                    
                    Row {
                        anchors {
                            fill: parent
                            margins: 10
                        }
                        spacing: 8
                        
                        Column {
                            width: 45
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                text: model.time || "--:--"
                                font.pixelSize: 14
                                font.bold: true
                                color: "#c41e3a"
                            }
                        }
                        
                        // Info Button (links)
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: "#444"
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "ⓘ"
                                font.pixelSize: 16
                                color: "#aaa"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    broadcastInfoSheet.broadcastId = model.id
                                    oe1.loadBroadcastInfo(model.id)
                                }
                            }
                        }
                        
                        Column {
                            width: parent.width - 180
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            
                            Label {
                                width: parent.width
                                text: model.title
                                font.pixelSize: 15
                                font.bold: true
                                color: "white"
                                elide: Text.ElideRight
                            }
                            
                            Label {
                                width: parent.width
                                text: model.subtitle || ""
                                font.pixelSize: 12
                                color: "#888"
                                elide: Text.ElideRight
                                visible: model.subtitle !== ""
                            }
                        }
                        
                        // Download Button
                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: model.hasStream ? "#2a6" : "#444"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: model.hasStream
                            
                            Label {
                                anchors.centerIn: parent
                                text: "⬇"
                                font.pixelSize: 16
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    downloadSheet.downloadTitle = model.title
                                    downloadSheet.downloadType = "broadcast"
                                    downloadSheet.broadcastId = model.id
                                    downloadSheet.podcastUrl = ""
                                    downloadSheet.downloadedFile = ""
                                    oe1.downloadBroadcast(model.id)
                                    downloadSheet.open()
                                }
                            }
                        }
                        
                        // Play Button
                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: model.hasStream ? "#c41e3a" : "#444"
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "▶"
                                font.pixelSize: 18
                                color: model.hasStream ? "white" : "#666"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                enabled: model.hasStream
                                onClicked: {
                                    appWindow.showTitle = model.title
                                    appWindow.showSubtitle = model.subtitle || ""
                                    appWindow.currentOnDemandId = model.id
                                    playingOnDemand = true
                                    oe1.getPlaybackUrl(model.id)
                                    pageStack.pop()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Podcasts Page
    Page {
        id: podcastsPage
        orientationLock: PageOrientation.LockPortrait
        
        tools: ToolBarLayout {
            ToolIcon {
                iconId: "toolbar-back"
                onClicked: pageStack.pop()
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            Rectangle {
                width: parent.width
                height: 60
                color: "#222"
                
                Label {
                    anchors.centerIn: parent
                    text: "Podcasts"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }
            }
            
            BusyIndicator {
                id: podcastsBusy
                anchors.horizontalCenter: parent.horizontalCenter
                running: false
                visible: running
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
            
            ListView {
                width: parent.width
                height: parent.height - 60
                model: podcastsModel
                clip: true
                
                delegate: Rectangle {
                    width: parent.width
                    height: 80
                    color: index % 2 === 0 ? "#252525" : "#2a2a2a"
                    
                    Row {
                        anchors {
                            fill: parent
                            margins: 12
                        }
                        spacing: 12
                        
                        Column {
                            width: parent.width - 60
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            
                            Label {
                                width: parent.width
                                text: model.title
                                font.pixelSize: 16
                                font.bold: true
                                color: "white"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                            }
                            
                            Label {
                                text: model.episodeCount + " Episoden"
                                font.pixelSize: 12
                                color: "#888"
                            }
                        }
                        
                        Label {
                            text: "›"
                            font.pixelSize: 32
                            color: "#666"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            episodesBusy.running = true
                            episodesModel.clear()
                            episodesPage.podcastTitle = model.title
                            oe1.loadPodcastEpisodes(model.id)
                            pageStack.push(episodesPage)
                        }
                    }
                }
            }
        }
    }
    
    // Podcast Episodes Page
    Page {
        id: episodesPage
        orientationLock: PageOrientation.LockPortrait
        property string podcastTitle: ""
        
        tools: ToolBarLayout {
            ToolIcon {
                iconId: "toolbar-back"
                onClicked: pageStack.pop()
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            Rectangle {
                width: parent.width
                height: 60
                color: "#222"
                
                Label {
                    anchors.centerIn: parent
                    text: episodesPage.podcastTitle
                    font.pixelSize: 20
                    font.bold: true
                    color: "white"
                    width: parent.width - 32
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            
            BusyIndicator {
                id: episodesBusy
                anchors.horizontalCenter: parent.horizontalCenter
                running: false
                visible: running
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
            
            ListView {
                width: parent.width
                height: parent.height - 60
                model: episodesModel
                clip: true
                
                delegate: Rectangle {
                    width: parent.width
                    height: 70
                    color: index % 2 === 0 ? "#252525" : "#2a2a2a"
                    
                    // Grüner Rand für heruntergeladene Episoden
                    Rectangle {
                        width: 4
                        height: parent.height
                        color: "#2a6"
                        visible: model.downloaded || false
                    }
                    
                    Row {
                        anchors {
                            fill: parent
                            margins: 10
                            leftMargin: (model.downloaded || false) ? 14 : 10
                        }
                        spacing: 8
                        
                        Column {
                            width: parent.width - 100
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            
                            Label {
                                width: parent.width
                                text: model.title || "Episode"
                                font.pixelSize: 14
                                color: "white"
                                elide: Text.ElideRight
                            }
                            
                            Label {
                                text: model.date || ""
                                font.pixelSize: 11
                                color: "#888"
                            }
                        }
                        
                        // Download Button
                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: model.url ? "#2a6" : "#444"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: model.url ? true : false
                            
                            Label {
                                anchors.centerIn: parent
                                text: "⬇"
                                font.pixelSize: 16
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (model.url) {
                                        downloadSheet.downloadTitle = model.title || "Episode"
                                        downloadSheet.downloadType = "podcast"
                                        downloadSheet.broadcastId = 0
                                        downloadSheet.podcastUrl = model.url
                                        downloadSheet.downloadedFile = ""
                                        oe1.downloadPodcastEpisode(model.url, model.title || "podcast")
                                        downloadSheet.open()
                                    }
                                }
                            }
                        }
                        
                        // Play Button
                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: model.url ? "#c41e3a" : "#444"
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "▶"
                                font.pixelSize: 18
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (model.url) {
                                        appWindow.showTitle = model.title || "Podcast"
                                        appWindow.showSubtitle = episodesPage.podcastTitle
                                        appWindow.playingOnDemand = true
                                        appWindow.currentOnDemandId = 0
                                        audioPlayer.stop()
                                        // Prüfe auf lokale Datei, sonst Proxy
                                        oe1.playLocalOrStream(model.url, model.title || "podcast")
                                        pageStack.pop()
                                        pageStack.pop()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Search Page
    Page {
        id: searchPage
        orientationLock: PageOrientation.LockPortrait
        
        tools: ToolBarLayout {
            ToolIcon {
                iconId: "toolbar-back"
                onClicked: pageStack.pop()
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            Rectangle {
                width: parent.width
                height: 60
                color: "#222"
                
                Label {
                    anchors.centerIn: parent
                    text: "Suche"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }
            }
            
            // Search input
            Rectangle {
                width: parent.width
                height: 60
                color: "#333"
                
                Row {
                    anchors {
                        fill: parent
                        margins: 8
                    }
                    spacing: 8
                    
                    TextField {
                        id: searchField
                        width: parent.width - 80
                        placeholderText: "Sendung suchen..."
                        
                        Keys.onReturnPressed: {
                            if (text.length >= 2) {
                                searchBusy.running = true
                                searchModel.clear()
                                oe1.search(text)
                            }
                        }
                    }
                    
                    Button {
                        text: "Suchen"
                        width: 60
                        onClicked: {
                            if (searchField.text.length >= 2) {
                                searchBusy.running = true
                                searchModel.clear()
                                oe1.search(searchField.text)
                            }
                        }
                    }
                }
            }
            
            BusyIndicator {
                id: searchBusy
                anchors.horizontalCenter: parent.horizontalCenter
                running: false
                visible: running
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
            
            // Results count
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: searchModel.count + " Ergebnisse"
                font.pixelSize: 14
                color: "#888"
                visible: searchModel.count > 0
            }
            
            ListView {
                width: parent.width
                height: parent.height - 140
                model: searchModel
                clip: true
                
                delegate: Rectangle {
                    width: parent.width
                    height: 70
                    color: index % 2 === 0 ? "#252525" : "#2a2a2a"
                    
                    Row {
                        anchors {
                            fill: parent
                            margins: 10
                        }
                        spacing: 8
                        
                        // Info Button (links)
                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            color: "#444"
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "ⓘ"
                                font.pixelSize: 16
                                font.bold: true
                                color: "#aaa"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    broadcastInfoSheet.broadcastId = model.id
                                    oe1.loadBroadcastInfo(model.id)
                                }
                            }
                        }
                        
                        // Text Column
                        Column {
                            width: parent.width - 130
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            
                            Label {
                                width: parent.width
                                text: model.title || ""
                                font.pixelSize: 14
                                font.bold: true
                                color: "white"
                                elide: Text.ElideRight
                            }
                            
                            Label {
                                width: parent.width
                                text: (model.date || "") + " " + (model.time || "") + " - " + (model.subtitle || "")
                                font.pixelSize: 11
                                color: "#888"
                                elide: Text.ElideRight
                            }
                        }
                        
                        // Download Button
                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            color: "#2a6"
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "⬇"
                                font.pixelSize: 11
                                font.bold: true
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    downloadSheet.downloadTitle = model.title || ""
                                    downloadSheet.downloadType = "broadcast"
                                    downloadSheet.broadcastId = model.id
                                    downloadSheet.podcastUrl = ""
                                    downloadSheet.downloadedFile = ""
                                    oe1.downloadBroadcast(model.id)
                                    downloadSheet.open()
                                }
                            }
                        }
                        
                        // Play Button
                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: "#c41e3a"
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "▶"
                                font.pixelSize: 22
                                font.bold: true
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    appWindow.showTitle = model.title || ""
                                    appWindow.showSubtitle = model.subtitle || ""
                                    appWindow.currentOnDemandId = model.id
                                    playingOnDemand = true
                                    oe1.getPlaybackUrl(model.id)
                                    pageStack.pop()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Menu
    Menu {
        id: mainMenu
        
        MenuLayout {
            MenuItem {
                text: "Qualität: Niedrig (2G)"
                onClicked: {
                    quality = "low"
                    if (audioPlayer.playing && !playingOnDemand) {
                        audioPlayer.stop()
                        audioPlayer.source = getStreamUrl()
                        audioPlayer.play()
                    }
                }
            }
            MenuItem {
                text: "Qualität: Mittel (3G)"
                onClicked: {
                    quality = "medium"
                    if (audioPlayer.playing && !playingOnDemand) {
                        audioPlayer.stop()
                        audioPlayer.source = getStreamUrl()
                        audioPlayer.play()
                    }
                }
            }
            MenuItem {
                text: "Qualität: Hoch (WLAN)"
                onClicked: {
                    quality = "high"
                    if (audioPlayer.playing && !playingOnDemand) {
                        audioPlayer.stop()
                        audioPlayer.source = getStreamUrl()
                        audioPlayer.play()
                    }
                }
            }
            MenuItem {
                text: "Sleep Timer..."
                onClicked: sleepTimerSheet.open()
            }
            MenuItem {
                text: "Zurück zum Live-Stream"
                visible: playingOnDemand
                onClicked: {
                    playingOnDemand = false
                    audioPlayer.stop()
                    audioPlayer.source = getStreamUrl()
                    audioPlayer.play()
                    oe1.refreshCurrentShow()
                }
            }
            MenuItem {
                text: "Über"
                onClicked: aboutDialog.open()
            }
        }
    }
    
    // Sleep Timer Sheet
    Sheet {
        id: sleepTimerSheet
        acceptButtonText: sleepTimerActive ? "Abbrechen" : "Start"
        rejectButtonText: "Schließen"
        
        onAccepted: {
            if (sleepTimerActive) {
                oe1.stopSleepTimer()
                sleepTimerActive = false
                sleepTimerRemaining = 0
            } else {
                var minutes = sleepMinutesModel.get(sleepMinutesList.currentIndex).value
                oe1.startSleepTimer(minutes)
                sleepTimerActive = true
            }
        }
        
        content: Rectangle {
            anchors.fill: parent
            color: "#000000"
            
            Column {
                anchors.centerIn: parent
                spacing: 20
                
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Sleep Timer"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }
                
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sleepTimerActive ? 
                          "Aktiv: " + formatSleepTime(sleepTimerRemaining) : 
                          "Nach dieser Zeit stoppt die Wiedergabe:"
                    font.pixelSize: 16
                    color: sleepTimerActive ? "#ffa500" : "#888"
                }
                
                ListView {
                    id: sleepMinutesList
                    width: 200
                    height: 200
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !sleepTimerActive
                    model: sleepMinutesModel
                    currentIndex: 2
                    clip: true
                    highlight: Rectangle {
                        color: "#c41e3a"
                        radius: 8
                    }
                    
                    delegate: Rectangle {
                        width: 200
                        height: 50
                        color: "transparent"
                        
                        Label {
                            anchors.centerIn: parent
                            text: model.label
                            font.pixelSize: 18
                            color: "white"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: sleepMinutesList.currentIndex = index
                        }
                    }
                }
            }
        }
    }
    
    ListModel {
        id: sleepMinutesModel
        ListElement { label: "15 Minuten"; value: 15 }
        ListElement { label: "30 Minuten"; value: 30 }
        ListElement { label: "45 Minuten"; value: 45 }
        ListElement { label: "60 Minuten"; value: 60 }
        ListElement { label: "90 Minuten"; value: 90 }
    }
    
    // About Dialog
    QueryDialog {
        id: aboutDialog
        titleText: "Ö1 Radio"
        message: "Version 1.3.2\n\nFunktionen:\n• Live-Stream mit Timeshift\n• 7 Tage Nachhören\n• Podcasts\n• Suche\n• Sendungsinfo\n• Sleep Timer\n\nFür MeeGo Harmattan"
        acceptButtonText: "OK"
    }
    
    // Broadcast Info Sheet
    Sheet {
        id: broadcastInfoSheet
        acceptButtonText: "Schließen"
        rejectButtonText: ""
        
        property string infoTitle: ""
        property string infoProgram: ""
        property string infoTime: ""
        property string infoDescription: ""
        property string infoModerator: ""
        property variant infoTopics: []
        property bool hasStream: false
        property int broadcastId: 0
        
        content: Flickable {
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: infoColumn.height
            clip: true
            
            Column {
                id: infoColumn
                width: parent.width
                spacing: 12
                
                Label {
                    text: broadcastInfoSheet.infoProgram
                    font.pixelSize: 14
                    color: "#c41e3a"
                    visible: broadcastInfoSheet.infoProgram !== ""
                }
                
                Label {
                    text: broadcastInfoSheet.infoTitle
                    font.pixelSize: 22
                    font.bold: true
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
                
                Label {
                    text: broadcastInfoSheet.infoTime
                    font.pixelSize: 16
                    color: "#888"
                    visible: broadcastInfoSheet.infoTime !== ""
                }
                
                Label {
                    text: "Moderation: " + broadcastInfoSheet.infoModerator
                    font.pixelSize: 14
                    color: "#aaa"
                    visible: broadcastInfoSheet.infoModerator !== ""
                }
                
                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#444"
                    visible: broadcastInfoSheet.infoDescription !== ""
                }
                
                Label {
                    text: broadcastInfoSheet.infoDescription
                    font.pixelSize: 16
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: broadcastInfoSheet.infoDescription !== ""
                }
                
                Label {
                    text: "Themen:"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#c41e3a"
                    visible: broadcastInfoSheet.infoTopics.length > 0
                }
                
                Repeater {
                    model: broadcastInfoSheet.infoTopics
                    Label {
                        text: "• " + modelData
                        font.pixelSize: 14
                        width: infoColumn.width
                        wrapMode: Text.WordWrap
                        color: "#ccc"
                    }
                }
                
                Button {
                    text: "Abspielen"
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: broadcastInfoSheet.hasStream && broadcastInfoSheet.broadcastId > 0
                    onClicked: {
                        appWindow.playingOnDemand = true
                        oe1.getPlaybackUrl(broadcastInfoSheet.broadcastId)
                        broadcastInfoSheet.accept()
                    }
                }
            }
        }
    }
    
    // Helper: Parse und zeige Broadcast Info
    Connections {
        target: oe1
        onBroadcastInfoChanged: {
            try {
                var info = JSON.parse(oe1.broadcastInfoJson)
                broadcastInfoSheet.infoTitle = info.title || ""
                broadcastInfoSheet.infoProgram = info.programTitle || ""
                broadcastInfoSheet.infoTime = (info.startTime && info.endTime) ? 
                    (info.startTime + " - " + info.endTime) : ""
                broadcastInfoSheet.infoDescription = info.description || ""
                broadcastInfoSheet.infoModerator = info.moderator || ""
                broadcastInfoSheet.infoTopics = info.topics || []
                broadcastInfoSheet.hasStream = info.hasStream || false
                broadcastInfoSheet.open()
            } catch(e) {
                console.log("Info parse error:", e)
            }
        }
    }
    
    // Download Progress Sheet
    Sheet {
        id: downloadSheet
        acceptButtonText: oe1.downloadActive ? "" : "Abspielen"
        rejectButtonText: oe1.downloadActive ? "Abbrechen" : "Schließen"
        
        property string downloadTitle: ""
        property string downloadType: ""
        property int broadcastId: 0
        property string podcastUrl: ""
        property string downloadedFile: ""
        
        onRejected: {
            // Nur abbrechen wenn Download noch läuft
            if (oe1.downloadActive) {
                oe1.cancelDownload()
            }
        }
        
        onAccepted: {
            // Heruntergeladene Datei abspielen
            if (downloadedFile !== "") {
                appWindow.showTitle = downloadTitle
                appWindow.showSubtitle = "Heruntergeladen"
                appWindow.playingOnDemand = true
                appWindow.currentOnDemandId = 0
                audioPlayer.source = "file://" + downloadedFile
                audioPlayer.play()
            }
        }
        
        content: Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20
            
            Label {
                text: "Download"
                font.pixelSize: 28
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Label {
                text: downloadSheet.downloadTitle
                font.pixelSize: 16
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
            
            ProgressBar {
                id: downloadProgressBar
                width: parent.width - 40
                anchors.horizontalCenter: parent.horizontalCenter
                minimumValue: 0
                maximumValue: 100
                value: oe1.downloadProgress
            }
            
            Label {
                text: oe1.downloadActive ? (oe1.downloadProgress + "%") : "Fertig!"
                font.pixelSize: 18
                anchors.horizontalCenter: parent.horizontalCenter
                color: oe1.downloadActive ? "#888" : "#2a6"
            }
            
            Label {
                text: "Speicherort: MyDocs/Oe1/"
                font.pixelSize: 12
                color: "#666"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !oe1.downloadActive
            }
        }
    }
    
    // Download finished handler
    Connections {
        target: oe1
        onDownloadFinished: {
            // Speichere Dateiname für Abspielen-Button
            downloadSheet.downloadedFile = oe1.downloadFilePath
        }
    }
    
    function formatTime(isoString) {
        if (!isoString) return "--:--"
        try {
            var d = new Date(isoString)
            var h = d.getHours()
            var m = d.getMinutes()
            return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
        } catch(e) {
            return "--:--"
        }
    }
    
    function formatDuration(ms) {
        if (!ms || ms <= 0) return "0:00"
        var secs = Math.floor(ms / 1000)
        var mins = Math.floor(secs / 60)
        secs = secs % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }
}
