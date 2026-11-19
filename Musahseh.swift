import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

private enum DefaultsKey {
    static let keepDisplayAwake = "keepDisplayAwake"
    static let closedLidMode = "closedLidMode"
    static let playCompletionSound = "playCompletionSound"
    static let restoreActive = "restoreActive"
    static let restoreEndDate = "restoreEndDate"
    static let restoreMode = "restoreMode"
}

private final class AwakeController {
    private var activity: NSObjectProtocol?
    private var systemSleepAssertion: IOPMAssertionID = 0

    func start(keepDisplayAwake: Bool, closedLidMode: Bool) {
        stop()
        var options: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
        if keepDisplayAwake {
            options.insert(.idleDisplaySleepDisabled)
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: "مصحصح فعّال بطلب المستخدم"
        )

        if closedLidMode {
            var assertion: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "مصحصح: الاستمرار مع الغطاء مغلقًا" as CFString,
                &assertion
            )
            if result == kIOReturnSuccess {
                systemSleepAssertion = assertion
            }
        }
    }

    func stop() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if systemSleepAssertion != 0 {
            IOPMAssertionRelease(systemSleepAssertion)
            systemSleepAssertion = 0
        }
    }

    deinit {
        stop()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let awakeController = AwakeController()
    private let defaults = UserDefaults.standard
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?

    private var isActive = false
    private var endDate: Date?
    private var activeMode = ""

    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let stopMenuItem = NSMenuItem(title: "إيقاف ومنح الماك حق النوم", action: #selector(stopAction), keyEquivalent: "")
    private let extendMenuItem = NSMenuItem(title: "أضف 30 دقيقة", action: #selector(extendThirtyMinutes), keyEquivalent: "")
    private let keepDisplayMenuItem = NSMenuItem(title: "أبقِ الشاشة مضاءة أيضًا", action: #selector(toggleKeepDisplayAwake), keyEquivalent: "")
    private let closedLidMenuItem = NSMenuItem(title: "استمر مع الغطاء مغلقًا (على الشاحن)", action: #selector(toggleClosedLidMode), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "تشغيل مصحصح عند تسجيل الدخول", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let soundMenuItem = NSMenuItem(title: "صوت عند انتهاء المؤقت", action: #selector(toggleCompletionSound), keyEquivalent: "")
    private var durationItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerDefaults()
        configureStatusItem()
        buildMenu()
        restoreSessionIfNeeded()
        startRefreshTimer()
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        awakeController.stop()
        refreshTimer?.invalidate()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            DefaultsKey.keepDisplayAwake: false,
            DefaultsKey.closedLidMode: false,
            DefaultsKey.playCompletionSound: true,
            DefaultsKey.restoreActive: false
        ])
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = menu
        statusItem.button?.toolTip = "مصحصح — إبقاء الماك مستيقظًا"
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        addDuration(title: "لا تنم", seconds: nil, mode: "indefinite")
        addDuration(title: "لمدة 30 دقيقة", seconds: 30 * 60, mode: "30m")
        addDuration(title: "لمدة ساعة", seconds: 60 * 60, mode: "1h")
        addDuration(title: "لمدة ساعتين", seconds: 2 * 60 * 60, mode: "2h")
        addDuration(title: "لمدة 4 ساعات", seconds: 4 * 60 * 60, mode: "4h")

        let endOfDay = NSMenuItem(title: "حتى نهاية اليوم", action: #selector(startUntilEndOfDay), keyEquivalent: "")
        endOfDay.target = self
        endOfDay.representedObject = "endOfDay"
        durationItems.append(endOfDay)
        menu.addItem(endOfDay)

        let custom = NSMenuItem(title: "مدة مخصصة…", action: #selector(startCustomDuration), keyEquivalent: "")
        custom.target = self
        custom.representedObject = "custom"
        durationItems.append(custom)
        menu.addItem(custom)

        menu.addItem(.separator())
        stopMenuItem.target = self
        menu.addItem(stopMenuItem)
        extendMenuItem.target = self
        menu.addItem(extendMenuItem)

        menu.addItem(.separator())
        keepDisplayMenuItem.target = self
        menu.addItem(keepDisplayMenuItem)
        closedLidMenuItem.target = self
        menu.addItem(closedLidMenuItem)
        soundMenuItem.target = self
        menu.addItem(soundMenuItem)
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())
        let lidInfo = NSMenuItem(title: "عن إغلاق غطاء الماك…", action: #selector(showLidInformation), keyEquivalent: "")
        lidInfo.target = self
        menu.addItem(lidInfo)

        let about = NSMenuItem(title: "حول مصحصح", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "إنهاء مصحصح", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addDuration(title: String, seconds: TimeInterval?, mode: String) {
        let item = NSMenuItem(title: title, action: #selector(startPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [
            "mode": mode,
            "seconds": seconds ?? -1
        ] as [String: Any]
        durationItems.append(item)
        menu.addItem(item)
    }

    private func startRefreshTimer() {
        refreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func tick() {
        if let endDate, isActive, endDate <= Date() {
            stopSession(expired: true)
        } else {
            refreshUI()
        }
    }

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let mode = info["mode"] as? String,
              let seconds = info["seconds"] as? TimeInterval else { return }
        startSession(seconds: seconds < 0 ? nil : seconds, mode: mode)
    }

    @objc private func startUntilEndOfDay() {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        startSession(seconds: max(60, tomorrow.timeIntervalSinceNow), mode: "endOfDay")
    }

    @objc private func startCustomDuration() {
        let alert = NSAlert()
        alert.messageText = "مدة مخصصة"
        alert.informativeText = "أدخل عدد الدقائق (من دقيقة إلى 7 أيام)."
        alert.alertStyle = .informational

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "مثال: 90"
        field.stringValue = "90"
        field.alignment = .right
        alert.accessoryView = field
        alert.addButton(withTitle: "ابدأ")
        alert.addButton(withTitle: "إلغاء")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(trimmed), (1...(7 * 24 * 60)).contains(minutes) else {
            showAlert(title: "المدة غير صحيحة", message: "اكتب رقمًا بين 1 و10080 دقيقة.", style: .warning)
            return
        }
        startSession(seconds: TimeInterval(minutes * 60), mode: "custom")
    }

    private func startSession(seconds: TimeInterval?, mode: String) {
        isActive = true
        endDate = seconds.map { Date().addingTimeInterval($0) }
        activeMode = mode
        awakeController.start(
            keepDisplayAwake: defaults.bool(forKey: DefaultsKey.keepDisplayAwake),
            closedLidMode: defaults.bool(forKey: DefaultsKey.closedLidMode)
        )
        persistSession()
        refreshUI()
    }

    @objc private func stopAction() {
        stopSession(expired: false)
    }

    private func stopSession(expired: Bool) {
        isActive = false
        endDate = nil
        activeMode = ""
        awakeController.stop()
        clearPersistedSession()
        refreshUI()
        if expired, defaults.bool(forKey: DefaultsKey.playCompletionSound) {
            NSSound(named: "Glass")?.play()
        }
    }

    @objc private func extendThirtyMinutes() {
        guard isActive, endDate != nil else { return }
        endDate = max(endDate ?? Date(), Date()).addingTimeInterval(30 * 60)
        activeMode = "custom"
        persistSession()
        refreshUI()
    }

    @objc private func toggleKeepDisplayAwake() {
        let newValue = !defaults.bool(forKey: DefaultsKey.keepDisplayAwake)
        defaults.set(newValue, forKey: DefaultsKey.keepDisplayAwake)
        if isActive {
            awakeController.start(
                keepDisplayAwake: newValue,
                closedLidMode: defaults.bool(forKey: DefaultsKey.closedLidMode)
            )
        }
        refreshUI()
    }

    @objc private func toggleClosedLidMode() {
        let newValue = !defaults.bool(forKey: DefaultsKey.closedLidMode)
        if newValue {
            let alert = NSAlert()
            alert.messageText = "تشغيل وضع الغطاء المغلق؟"
            alert.informativeText = "استخدم هذا الوضع والماك موصول بالشاحن، واتركه في مكان جيد التهوية. لا تضعه في حقيبة وهو يعمل. قد يوقف macOS الجهاز رغم ذلك لحماية البطارية أو عند ارتفاع الحرارة."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "تشغيل")
            alert.addButton(withTitle: "إلغاء")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        defaults.set(newValue, forKey: DefaultsKey.closedLidMode)
        if isActive {
            awakeController.start(
                keepDisplayAwake: defaults.bool(forKey: DefaultsKey.keepDisplayAwake),
                closedLidMode: newValue
            )
        }
        refreshUI()
    }

    @objc private func toggleCompletionSound() {
        defaults.set(!defaults.bool(forKey: DefaultsKey.playCompletionSound), forKey: DefaultsKey.playCompletionSound)
        refreshUI()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            showAlert(title: "غير مدعوم", message: "يتطلب التشغيل عند تسجيل الدخول macOS 13 أو أحدث.", style: .warning)
            return
        }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: "تعذّر تغيير الإعداد",
                message: "انقل مصحصح إلى مجلد التطبيقات ثم أعد المحاولة.\n\n\(error.localizedDescription)",
                style: .warning
            )
        }
        refreshUI()
    }

    @objc private func showLidInformation() {
        showAlert(
            title: "إغلاق غطاء الماك",
            message: "فعّل «استمر مع الغطاء مغلقًا» ووصل الماك بالشاحن قبل إغلاقه. يطلب مصحصح من macOS إبقاء مهام النظام مستمرة، لكن قد يفرض النظام السكون حسب موديل الماك أو البطارية أو الحرارة.\n\nلأفضل نتيجة مضمونة من Apple، استخدم الشاحن وشاشة خارجية. لا تضع الماك في حقيبة وهو يعمل والغطاء مغلق.",
            style: .informational
        )
    }

    @objc private func showAbout() {
        showAlert(
            title: "مصحصح ☕️",
            message: "تطبيق خفيف لإبقاء الماك مستيقظًا وقت العمل أو التنزيلات أو العروض. لا يحتاج صلاحيات مدير النظام ولا يغيّر إعدادات الطاقة الدائمة.",
            style: .informational
        )
    }

    @objc private func quitApp() {
        stopSession(expired: false)
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "حسنًا")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func persistSession() {
        defaults.set(true, forKey: DefaultsKey.restoreActive)
        defaults.set(endDate?.timeIntervalSince1970 ?? 0, forKey: DefaultsKey.restoreEndDate)
        defaults.set(activeMode, forKey: DefaultsKey.restoreMode)
    }

    private func clearPersistedSession() {
        defaults.set(false, forKey: DefaultsKey.restoreActive)
        defaults.removeObject(forKey: DefaultsKey.restoreEndDate)
        defaults.removeObject(forKey: DefaultsKey.restoreMode)
    }

    private func restoreSessionIfNeeded() {
        guard defaults.bool(forKey: DefaultsKey.restoreActive) else { return }
        let storedTime = defaults.double(forKey: DefaultsKey.restoreEndDate)
        let storedEndDate = storedTime > 0 ? Date(timeIntervalSince1970: storedTime) : nil
        if let storedEndDate, storedEndDate <= Date() {
            clearPersistedSession()
            return
        }
        isActive = true
        endDate = storedEndDate
        activeMode = defaults.string(forKey: DefaultsKey.restoreMode) ?? "custom"
        awakeController.start(
            keepDisplayAwake: defaults.bool(forKey: DefaultsKey.keepDisplayAwake),
            closedLidMode: defaults.bool(forKey: DefaultsKey.closedLidMode)
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    private func refreshUI() {
        statusItem.button?.image = makeSaudiCoffeeIcon(active: isActive)
        statusItem.button?.appearsDisabled = false

        statusMenuItem.title = statusText()
        stopMenuItem.isEnabled = isActive
        extendMenuItem.isHidden = !isActive || endDate == nil
        keepDisplayMenuItem.state = defaults.bool(forKey: DefaultsKey.keepDisplayAwake) ? .on : .off
        closedLidMenuItem.state = defaults.bool(forKey: DefaultsKey.closedLidMode) ? .on : .off
        soundMenuItem.state = defaults.bool(forKey: DefaultsKey.playCompletionSound) ? .on : .off

        if #available(macOS 13.0, *) {
            launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginMenuItem.state = .off
        }

        for item in durationItems {
            let mode: String?
            if let info = item.representedObject as? [String: Any] {
                mode = info["mode"] as? String
            } else {
                mode = item.representedObject as? String
            }
            item.state = isActive && mode == activeMode ? .on : .off
        }
    }

    private func makeSaudiCoffeeIcon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .high
            let opacity: CGFloat = active ? 1.0 : 0.82

            // بخار القهوة
            let steamColor = NSColor(calibratedRed: 0.63, green: 0.31, blue: 0.12, alpha: active ? 0.95 : 0.62)
            for x in [8.0, 13.5] {
                let steam = NSBezierPath()
                steam.move(to: NSPoint(x: x, y: 14.2))
                steam.curve(
                    to: NSPoint(x: x + 0.4, y: 20.1),
                    controlPoint1: NSPoint(x: x + 2.0, y: 16.2),
                    controlPoint2: NSPoint(x: x - 1.6, y: 18.0)
                )
                steam.lineWidth = 1.25
                steam.lineCapStyle = .round
                steamColor.setStroke()
                steam.stroke()
            }

            // جسم الفنجال السعودي بلا مقبض
            let cup = NSBezierPath()
            cup.move(to: NSPoint(x: 3.1, y: 12.8))
            cup.curve(to: NSPoint(x: 6.3, y: 3.5), controlPoint1: NSPoint(x: 3.6, y: 8.2), controlPoint2: NSPoint(x: 4.8, y: 4.4))
            cup.curve(to: NSPoint(x: 15.7, y: 3.5), controlPoint1: NSPoint(x: 8.5, y: 2.5), controlPoint2: NSPoint(x: 13.5, y: 2.5))
            cup.curve(to: NSPoint(x: 18.9, y: 12.8), controlPoint1: NSPoint(x: 17.2, y: 4.4), controlPoint2: NSPoint(x: 18.4, y: 8.2))
            cup.close()

            NSGraphicsContext.saveGraphicsState()
            cup.addClip()
            let goldGradient = NSGradient(colors: [
                NSColor(calibratedRed: 1.00, green: 0.86, blue: 0.42, alpha: opacity),
                NSColor(calibratedRed: 0.91, green: 0.61, blue: 0.13, alpha: opacity)
            ])!
            goldGradient.draw(in: NSRect(x: 3, y: 2.5, width: 16, height: 11), angle: -90)

            // شريط أخضر وزخرفة ذهبية مستوحاة من فناجيل القهوة السعودية
            NSColor(calibratedRed: 0.04, green: 0.42, blue: 0.24, alpha: opacity).setFill()
            NSBezierPath(rect: NSRect(x: 3, y: 6.6, width: 16, height: 2.25)).fill()
            NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.32, alpha: opacity).setFill()
            for x in stride(from: 5.0, through: 17.0, by: 4.0) {
                let diamond = NSBezierPath()
                diamond.move(to: NSPoint(x: x, y: 7.72))
                diamond.line(to: NSPoint(x: x + 1.0, y: 8.5))
                diamond.line(to: NSPoint(x: x + 2.0, y: 7.72))
                diamond.line(to: NSPoint(x: x + 1.0, y: 6.92))
                diamond.close()
                diamond.fill()
            }
            NSGraphicsContext.restoreGraphicsState()

            NSColor(calibratedRed: 0.45, green: 0.24, blue: 0.07, alpha: opacity).setStroke()
            cup.lineWidth = 0.7
            cup.stroke()

            // حافة الفنجال والقهوة
            let rim = NSBezierPath(ovalIn: NSRect(x: 2.9, y: 11.2, width: 16.2, height: 3.25))
            NSColor(calibratedRed: 0.96, green: 0.74, blue: 0.23, alpha: opacity).setFill()
            rim.fill()
            NSColor(calibratedRed: 0.30, green: 0.12, blue: 0.035, alpha: active ? 1.0 : 0.84).setFill()
            NSBezierPath(ovalIn: NSRect(x: 4.1, y: 11.8, width: 13.8, height: 1.9)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = active ? "مصحصح فعّال — فنجال قهوة سعودي" : "مصحصح متوقف — فنجال قهوة سعودي"
        return image
    }

    private func statusText() -> String {
        guard isActive else { return "متوقف — الماك ينام كالمعتاد" }
        guard let endDate else {
            return defaults.bool(forKey: DefaultsKey.keepDisplayAwake)
                ? "فعّال — الماك والشاشة سيبقيان مستيقظين"
                : "فعّال — الماك مستيقظ والشاشة يمكن أن تنطفئ"
        }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        return "فعّال — متبقٍ \(formatDuration(remaining))"
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
