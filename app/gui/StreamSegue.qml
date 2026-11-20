import QtQuick 2.0
import QtQuick.Controls
import QtQuick.Window 2.2

import SdlGamepadKeyNavigation 1.0
import Session 1.0
import SystemProperties 1.0
import StreamingPreferences 1.0

import "theme"
import "Brand.js" as Brand

Item {
    property Session session
    // 策略开启时我们在串流窗口出现前就把 segue 弹掉，让主窗口回到列表页；
    // 这样 sessionFinished() 就不该再弹一次（否则会连列表页一起弹掉）。
    property bool poppedEarly: false
    // 拆分模式：segue 不入栈也不显示，主窗口始终停在列表页，
    // 串流画面由 SDL 自己创建的窗口呈现。
    property bool detached: false
    property string appName

    // 正在启动的这个游戏的封面。加载页用它做背景，而不是首页的主机壁纸——
    // 你正要进的是这个游戏，画面就该先切过去。取不到时退回主机壁纸。
    property string boxArtUrl: ""

    // 自带背景，main.qml 的全局壁纸层不用再垫一层
    readonly property bool usesOwnBackground: true
    property string stageText : isResume ? qsTr("Resuming %1...").arg(appName) :
                                           qsTr("Starting %1...").arg(appName)
    property bool isResume : false
    property bool quitAfter : false

    // 退出组合键提示随设置走：玩家改了组合键，提示不能还教默认那套。
    // 按键名按当前手柄风格显示（PS 显示 Options/Share/✕，Switch 显示 +/−），
    // swapFaceButtons 时补偿到实际要按的物理键
    function quitComboHintText()
    {
        var nav = SdlGamepadKeyNavigation
        var swap = StreamingPreferences.swapFaceButtons
        var lb = nav.leftShoulderName()
        var rb = nav.rightShoulderName()
        var face = function(i) { return nav.faceButtonGlyph(swap ? (i ^ 1) : i) }
        var shoulders = lb + "+" + rb
        switch (StreamingPreferences.gamepadQuitCombo) {
        case StreamingPreferences.GQC_SELECT_L1_R1_Y:
            return nav.selectButtonName() + "+" + shoulders + "+" + face(3)
        case StreamingPreferences.GQC_START_L1_R1_A:
            return nav.startButtonName() + "+" + shoulders + "+" + face(0)
        case StreamingPreferences.GQC_START_L1_R1_B:
            return nav.startButtonName() + "+" + shoulders + "+" + face(1)
        case StreamingPreferences.GQC_L1_R1_X_Y:
            return shoulders + "+" + face(2) + "+" + face(3)
        case StreamingPreferences.GQC_L1_R1_A_B:
            return shoulders + "+" + face(0) + "+" + face(1)
        default:
            return nav.startButtonName() + "+" + nav.selectButtonName() + "+" + shoulders
        }
    }

    function stageStarting(stage)
    {
        // Update the spinner text
        stageText = qsTr("Starting %1...").arg(stage)
    }

    function stageFailed(stage, errorCode, failingPorts)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = qsTr("Starting %1 failed: Error %2").arg(stage).arg(errorCode)

        if (failingPorts) {
            streamSegueErrorDialog.text += "\n\n" + qsTr("Check your firewall and port forwarding rules for port(s): %1").arg(failingPorts)
        }
    }

    function hideForStreaming()
    {
        if (StreamingPreferences.keepListWindowVisible) {
            // 主窗口会被保留，所以这些内容要继续显示，否则窗口里只剩一张背景
        } else {
        // Hide the UI contents so the user doesn't
        // see them briefly when we pop off the StackView
        stageSpinner.visible = false
        stageLabel.visible = false
        hintText.visible = false
        }

        // 窗口本身不在这里藏，由 Session::exec() 在串流窗口进入全屏之后隐藏。
        // 提前藏的话，macOS 切进新 Space 的整个动画期间旧 Space 露出来的是桌面，
        // 而不是这层已经全黑的幕。
    }

    function connectionStarted()
    {
        // 淡出到全黑。Session::exec() 会等这条动画跑完再创建串流窗口，
        // 所以交接是在一块纯黑上完成的，中间不会闪。
        backgroundZoomAnimation.stop()
        // 注意：CLI 拉起的实例也会用本文件（CliStartStreamSegue.qml 的
        // onSessionCreated 里 createObject("StreamSegue.qml") 并 push），但带
        // quitAfter: true。若不排除它，次实例会被 pop 回 CLI 自己的加载页，
        // 于是每路串流旁边都多挂一个"正在启动…"窗口。
        if (StreamingPreferences.keepListWindowVisible && !quitAfter) {
            // 关键：这层淡到全黑的幕原本假定窗口随后会被隐藏。
            // 保留主窗口时必须跳过它，否则屏幕上留下的就是一块纯黑。
            contentRoot.opacity = 1

            // 把 segue 弹掉，让主窗口回到应用/主机列表页。
            // 依据 Qt 文档的 Item Ownership：push 已存在对象的 pop 不会销毁该对象
            // （这里是 createObject 后再 push 的），所以 C++ 侧连到本对象的
            // sessionFinished / readyForDeletion 等信号仍然有效。
            // 注意：push 时 pushExit 已经把上一页的 opacity 动画到 0 了
            // （main.qml:270-274）。用 Immediate pop 不会跑 popEnter，
            // 那一页就永远停在透明状态 —— 看着像纯黑，而且点不到。
            // 所以先拿到它，pop 之后手动复位。
            if (!detached) {
                var reveal = stackView.get(stackView.depth - 2)
                stackView.pop(StackView.Immediate)
                if (reveal) {
                    // pushExit 已把上一页淡到 0，而 Immediate pop 不跑 popEnter，
                    // 不复位就会一直是透明的（看着像纯黑且点不到）。
                    reveal.opacity = 1
                    reveal.x = 0
                }
                poppedEarly = true
            }
            return
        }
        exitAnimation.start()
    }

    function displayLaunchError(text)
    {
        // Display the error dialog after Session::exec() returns
        streamSegueErrorDialog.text = text
        console.error(text)
    }

    function quitStarting()
    {
        // Avoid the push transition animation
        var component = Qt.createComponent("QuitSegue.qml")
        var quitSegue = component.createObject(stackView, {"appName": appName})
        if (detached) {
            // 拆分模式：主窗口一直在列表页，不要插入退出覆盖层
            quitSegue.destroy()
        } else if (poppedEarly) {
            // 主窗口已经回到列表页了。这里必须 push：再 replace currentItem
            // 会把列表页本身换掉，QuitSegue 自己 pop 之后就落到 PcView 而不是 AppView。
            stackView.push(quitSegue, StackView.Immediate)
        } else {
            stackView.replace(stackView.currentItem, quitSegue, StackView.Immediate)
        }

        // Show the Qt window again to show quit segue
        window.visible = true
    }

    function sessionFinished(portTestResult)
    {
        if (portTestResult !== 0 && portTestResult !== -1 && streamSegueErrorDialog.text) {
            streamSegueErrorDialog.text += "\n\n" + Brand.text(qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network."))
        }

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()

        // Pop the StreamSegue off the stack if this is a GUI-based app launch
        if (!quitAfter && !poppedEarly && !detached) {
            stackView.pop()
        }

        if (quitAfter && !streamSegueErrorDialog.text) {
            // If this was a CLI launch without errors, exit now
            Qt.quit()
        }
        else {
            // Show the Qt window again after streaming
            window.visible = true

            // Display any launch errors. We do this after
            // the Qt UI is visible again to prevent losing
            // focus on the dialog which would impact gamepad
            // users.
            if (streamSegueErrorDialog.text) {
                streamSegueErrorDialog.quitAfter = quitAfter
                streamSegueErrorDialog.open()
            }
        }
    }

    function sessionReadyForDeletion()
    {
        // Garbage collect the Session object since it's pretty heavyweight
        // and keeps other libraries (like SDL_TTF) around until it is deleted.
        session = null
        gc()

        if (detached) {
            // 先解除 AppView 的启动护栏，再自毁
            // （没入栈的 segue 不会被 StackView 回收，必须自己 destroy）
            if (window.detachedSegue === this) {
                window.detachedSegue = null
            }
            destroy()
        }
    }

    StackView.onDeactivating: {
        // Show the toolbar again when popped off the stack
        toolBar.shown = true

        // Re-enable GUI gamepad usage now
        SdlGamepadKeyNavigation.enable()
    }

    function activate() {
        // Hide the toolbar before we start loading
        if (!detached) {
            toolBar.shown = false
        }

        // Hook up our signals
        session.stageStarting.connect(stageStarting)
        session.stageFailed.connect(stageFailed)
        session.connectionStarted.connect(connectionStarted)
        session.displayLaunchError.connect(displayLaunchError)
        session.quitStarting.connect(quitStarting)
        session.sessionFinished.connect(sessionFinished)
        session.readyForDeletion.connect(sessionReadyForDeletion)

        // Ensure the SystemProperties async thread is finished,
        // since it may currently be using the SDL video subsystem
        SystemProperties.waitForAsyncLoad()

        enterAnimation.start()
        backgroundZoomAnimation.start()

        // Kick off the stream
        streamLoader.active = true
    }

    StackView.onActivated: {
        if (!detached) {
            activate()
        }
    }

    // 拆分模式下不会被 push，也就永远不会 activate；
    // 而 createObject 会同步触发本回调，所以 detached 必须作为初始属性传入。
    Component.onCompleted: {
        if (detached) {
            activate()
        }
    }

    // 上一页（游戏列表）的背景先留在最底层。封面在它上面淡入，
    // 这样从列表切到加载页不是整张图硬换，而是接着上一张继续。
    Image {
        id: previousBackground

        anchors.fill: parent
        source: window.backgroundImageUrl
        visible: source != ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: 0.3
        z: -3
    }

    // 封面加载失败过一次就别再试了，直接退回主机壁纸。
    // 只看 boxArtUrl 是不是空串不够：地址在但图取不下来（换过封面、缓存失效、
    // 主机没这张图）时 status 会停在 Error，而 opacity 绑的是 status === Ready，
    // 结果整层永远是全透明的，加载页只剩一块压暗的底。
    property bool boxArtFailed: false

    onBoxArtUrlChanged: boxArtFailed = false

    Image {
        id: segueBackground

        anchors.fill: parent
        source: (boxArtUrl !== "" && !boxArtFailed)
                    ? boxArtUrl
                    : (window.backgroundImageUrl !== "" ? window.backgroundImageUrl
                                                        : "qrc:/res/gura.png")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        z: -2

        // 声明式地跟着加载状态淡入。不要用 onStatusChanged 触发动画：
        // 封面通常已经在缓存里，status 在处理器挂上之前就已经是 Ready，
        // 那样动画永远不会触发，背景会一直停在全透明。
        opacity: status === Image.Ready ? 1 : 0

        // 失败要靠事件记下来。同样因为缓存的关系，也可能在处理器挂上之前
        // 就已经是 Error 了，所以创建时再补查一次。
        onStatusChanged: if (status === Image.Error) boxArtFailed = true
        Component.onCompleted: if (status === Image.Error) boxArtFailed = true

        Behavior on opacity {
            NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
        }

        // 缓慢推近，让等待的这几秒不是一张死图
        transform: Scale {
            id: backgroundZoom
            origin.x: segueBackground.width / 2
            origin.y: segueBackground.height / 2
        }
    }

    ParallelAnimation {
        id: backgroundZoomAnimation
        NumberAnimation {
            target: backgroundZoom; property: "xScale"
            from: 1.0; to: 1.08; duration: 14000; easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: backgroundZoom; property: "yScale"
            from: 1.0; to: 1.08; duration: 14000; easing.type: Easing.InOutSine
        }
    }

    // 压暗，保证进度条和文字在任何封面上都读得清
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b,
                       StreamingPreferences.backgroundOverlayOpacity / 100.0)
        z: -1
    }

    // 进入串流时盖上来的幕，替代原来「一帧之内直接隐藏窗口」的硬切。
    //
    // 这一层刻意用纯黑而不是 Theme.ink：接手它的是 SDL 串流窗口，而 SDL 窗口在拿到
    // 第一帧之前就是纯黑的（实测 macOS 上是 0,0,0）。两边同色，交接那一刻才没有色阶跳变。
    Rectangle {
        id: exitVeil
        anchors.fill: parent
        color: "black"
        opacity: 0
        visible: opacity > 0
        z: 10
    }

    ParallelAnimation {
        id: enterAnimation
        NumberAnimation {
            target: contentRoot; property: "opacity"
            from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: contentShift; property: "y"
            from: 14; to: 0; duration: 480; easing.type: Easing.OutCubic
        }
    }

    // 进入串流：内容淡出、背景轻微推近、黑幕盖上来，三件事一起做，
    // 读起来像是「被带进游戏」而不是窗口突然不见了。
    ParallelAnimation {
        id: exitAnimation

        NumberAnimation {
            target: contentRoot; property: "opacity"
            to: 0; duration: 260; easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: backgroundZoom; property: "xScale"
            to: 1.14; duration: 340; easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: backgroundZoom; property: "yScale"
            to: 1.14; duration: 340; easing.type: Easing.InOutQuad
        }
        SequentialAnimation {
            NumberAnimation {
                target: exitVeil; property: "opacity"
                to: 1; duration: 340; easing.type: Easing.InOutQuad
            }
            ScriptAction {
                script: hideForStreaming()
            }
        }
    }

    Timer {
        id: startSessionTimer
        onTriggered: {
            // Garbage collect QML stuff before we start streaming,
            // since we'll probably be streaming for a while and we
            // won't be able to GC during the stream.
            gc()

            // Run the streaming session to completion
            session.start()
        }
    }

    Loader {
        id: streamLoader
        active: false
        asynchronous: true

        onLoaded: {
            // Set the hint text. We do this here rather than
            // in the hintText control itself to synchronize
            // with Session.exec() which requires no concurrent
            // gamepad usage.
            hintText.text = qsTr("Tip:") + " " + qsTr("Press %1 to disconnect your session").arg(SdlGamepadKeyNavigation.getConnectedGamepads() > 0 &&
                                                  SdlGamepadKeyNavigation.gamepadQuitComboEnabled() ?
                                                  quitComboHintText() : qsTr("Ctrl+Alt+Shift+Q"))

            // Stop GUI gamepad usage now
            SdlGamepadKeyNavigation.disable()

            // Initialize the session and probe for host/client capabilities
            if (!session.initialize(window)) {
                sessionFinished(0);
                sessionReadyForDeletion();
                return;
            }

            // This spinner is shown only after session.initialize() has completed
            // to prevent active animations from running during decoder probing,
            // which causes re-entrant event loop livelocks with libdecor-gtk.
            stageSpinner.visible = true

            // Don't wait unless we have toasts to display
            startSessionTimer.interval = 0

            // Display the toasts together in a vertical centered arrangement
            var yOffset = 0
            for (var i = 0; i < session.launchWarnings.length; i++) {
                var text = session.launchWarnings[i]
                console.warn(text)

                // Show the tooltip for 3 seconds
                var toast = Qt.createQmlObject('import QtQuick.Controls 2.2; ToolTip {}', parent, '')
                toast.timeout = 3000
                toast.text = text
                toast.y += yOffset
                toast.visible = true

                // Offset the next toast below the previous one
                yOffset = toast.y + toast.padding + toast.height

                // Allow an extra 500 ms for the tooltip's fade-out animation to finish
                startSessionTimer.interval = toast.timeout + 500;
            }

            // Start the timer to wait for toasts (or start the session immediately)
            startSessionTimer.start()
        }

        sourceComponent: Item {}
    }

    Item {
        id: contentRoot

        anchors.fill: parent
        opacity: 0

        // 淡入的同时轻微上浮
        transform: Translate {
            id: contentShift
            y: 14
        }

        // 阶段文字 + 斜条纹读条。转圈的 BusyIndicator 换成 HardProgress。
        // stageSpinner 这个 id 和 visible 语义保持不变：spinnerTimer 和
        // hideForStreaming() 都在用。
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.spaceXl * 2, 620)
            spacing: Theme.spaceLg

            Text {
                id: stageLabel

                width: parent.width
                text: stageText
                color: Theme.text
                font.family: Theme.fontSans
                font.pointSize: 24
                font.weight: Font.ExtraBold
                font.letterSpacing: Theme.trackingTight(24)
                // 左对齐。居中大字是那种「优雅」排版的做法，这套风格里所有东西都
                // 咬着一条左基线走（工具栏字标、卡片标题、设置行），读条上的阶段文字
                // 也一样 —— 而且它会随阶段变长变短，居中的话每换一句都在左右横跳。
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
            }

            HardProgress {
                id: stageSpinner

                width: parent.width
                visible: false
            }
        }

        Text {
            id: hintText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 50
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.textDim
            font.family: Theme.fontMono
            font.pointSize: Theme.fontBody
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.Wrap
        }
    }
}
