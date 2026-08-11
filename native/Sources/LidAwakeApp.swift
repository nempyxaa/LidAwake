import AppKit
import Foundation
import ServiceManagement
import UserNotifications

private struct Copy {
    let sleeps, awake, battery, ac, reverts: String
    let keep, turnOff, sleep, batteryCaption, acCaption: String
    let settings, notifications, thermal, floor: String
    let offBody, acBody, lowBody, batteryBody, failBody: String
    let openBody, autoACBody, revokedBody, hotPrefix, autoBatteryBody: String

    static func current(floor: Int) -> Copy {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        switch language {
        case "de": return Copy(
            sleeps: "Deckel zu: Ruhezustand", awake: "Deckel zu: bleibt wach", battery: "Akku:", ac: "Strom: Netz",
            reverts: "Endet bei: Deckel auf, unter \(floor)%, oder am Netz",
            keep: "Mit geschlossenem Deckel wach halten", turnOff: "Wachhalten ausschalten", sleep: "Jetzt in den Ruhezustand",
            batteryCaption: "Vorübergehend, endet unter \(floor)%", acCaption: "Am Netz, kein Akkulimit",
            settings: "Einstellungen", notifications: "Mitteilungen anzeigen", thermal: "Bei Hitze automatisch schlafen", floor: "Akku-Mindeststand",
            offBody: "Deckel schließen versetzt den Mac wie gewohnt in den Ruhezustand.", acBody: "Der Mac läuft mit geschlossenem Deckel weiter (am Netz).",
            lowBody: "Akku zu niedrig, Wachhalten abgelehnt, Netzteil anschliessen.",
            batteryBody: "Mac bleibt mit geschlossenem Deckel im Akkubetrieb wach, Stromsparmodus an. Endet bei Deckel auf, wenig Akku oder Netz.",
            failBody: "Konnte Wachhalten nicht aktivieren: pmset braucht die passwortlose sudo-Regel (siehe README). Nichts geaendert.",
            openBody: "Deckel offen: Akku-Uebersteuerung beendet, Standard-Ruhezustand wieder aktiv.",
            autoACBody: "Am Netz: Nachtmodus automatisch an. Zum Ausschalten den Mond anklicken.",
            revokedBody: "Akku unter \(floor)%: Uebersteuerung beendet, Mac schlaeft bei geschlossenem Deckel.",
            hotPrefix: "Ruhezustand wegen Ueberhitzung um", autoBatteryBody: "Im Akkubetrieb: Nachtmodus aus, Deckel schliessen versetzt in den Ruhezustand.")
        case "fr": return Copy(
            sleeps: "Capot fermé : veille", awake: "Capot fermé : reste actif", battery: "Batterie :", ac: "Alim. : secteur",
            reverts: "Fin si : capot ouvert, sous \(floor)%, ou secteur",
            keep: "Rester actif capot fermé", turnOff: "Désactiver le maintien actif", sleep: "Mettre en veille",
            batteryCaption: "Temporaire, fin sous \(floor)%", acCaption: "Sur secteur, sans limite de batterie",
            settings: "Réglages", notifications: "Afficher les notifications", thermal: "Veille auto en cas de surchauffe", floor: "Seuil de batterie",
            offBody: "Fermer le capot met le Mac en veille comme d'habitude.", acBody: "Le Mac continue capot ferme (sur secteur).",
            lowBody: "Batterie trop basse, maintien refuse, branchez l'alimentation.",
            batteryBody: "Le Mac reste actif capot ferme sur batterie, mode economie d'energie active. Fin si capot ouvert, batterie faible ou secteur.",
            failBody: "Activation impossible: pmset requiert la regle sudo sans mot de passe (voir README). Rien change.",
            openBody: "Capot ouvert: derogation batterie terminee, veille par defaut retablie.",
            autoACBody: "Sur secteur: mode nuit active automatiquement. Cliquez la lune pour desactiver.",
            revokedBody: "Batterie sous \(floor)%: derogation terminee, le Mac se met en veille capot ferme.",
            hotPrefix: "Mise en veille pour surchauffe a", autoBatteryBody: "Sur batterie: mode nuit desactive, fermer le capot met en veille.")
        case "es": return Copy(
            sleeps: "Tapa cerrada: en reposo", awake: "Tapa cerrada: sigue activo", battery: "Batería:", ac: "Corriente: red",
            reverts: "Termina si: abres la tapa, bajo \(floor)%, o al enchufar",
            keep: "Mantener activo con la tapa cerrada", turnOff: "Desactivar mantener activo", sleep: "Poner en reposo",
            batteryCaption: "Temporal, termina bajo \(floor)%", acCaption: "Con corriente, sin límite de batería",
            settings: "Ajustes", notifications: "Mostrar notificaciones", thermal: "Reposo automático si se calienta", floor: "Umbral de batería",
            offBody: "Cerrar la tapa pone el Mac en reposo como siempre.", acBody: "El Mac sigue con la tapa cerrada (con corriente).",
            lowBody: "Bateria muy baja, se rechazo, conecta la corriente.",
            batteryBody: "El Mac sigue activo con la tapa cerrada en bateria, modo de bajo consumo activado. Termina al abrir, bateria baja o corriente.",
            failBody: "No se pudo activar: pmset necesita la regla sudo sin contrasena (ver README). Nada cambio.",
            openBody: "Tapa abierta: anulacion en bateria terminada, reposo por defecto restaurado.",
            autoACBody: "Con corriente: modo noche activado automaticamente. Haz clic en la luna para desactivar.",
            revokedBody: "Bateria bajo \(floor)%: anulacion terminada, el Mac entra en reposo con la tapa cerrada.",
            hotPrefix: "En reposo por sobrecalentamiento a las", autoBatteryBody: "En bateria: modo noche desactivado, cerrar la tapa pone en reposo.")
        case "ru": return Copy(
            sleeps: "Крышка закрыта: сон", awake: "Крышка закрыта: не спит", battery: "Батарея:", ac: "Питание: сеть",
            reverts: "Вернётся: открыл крышку, ниже \(floor)%, или зарядка",
            keep: "Не спать с закрытой крышкой", turnOff: "Выключить «не спать»", sleep: "Уснуть сейчас",
            batteryCaption: "Временно, вернётся ниже \(floor)%", acCaption: "На зарядке, без лимита батареи",
            settings: "Настройки", notifications: "Показывать уведомления", thermal: "Засыпать при перегреве", floor: "Порог батареи",
            offBody: "Крышка теперь усыпляет Mac как обычно.", acBody: "Mac продолжит работать с закрытой крышкой (на питании).",
            lowBody: "Батарея слишком низкая, оверрайд не включён, подключи питание.",
            batteryBody: "Mac не уснёт с закрытой крышкой на батарее, включён режим энергосбережения. Снимется само: открытие крышки, низкий заряд, или питание.",
            failBody: "Не удалось включить: pmset нужен беспарольный sudo (см. README). Ничего не изменилось.",
            openBody: "Крышка открыта: батарейный оверрайд снят, дефолт снова сон.",
            autoACBody: "На питании: ночной режим включён автоматически. Выключить - клик по луне.",
            revokedBody: "Батарея ниже \(floor)%: оверрайд снят, Mac уснёт с крышкой.",
            hotPrefix: "Ушёл в сон из-за перегрева в", autoBatteryBody: "На батарее: ночной режим выключен, крышка усыпляет как обычно.")
        default: return Copy(
            sleeps: "Lid closed: sleeps", awake: "Lid closed: staying awake", battery: "Battery:", ac: "Power: AC",
            reverts: "Reverts on: lid open, under \(floor)%, plugged in",
            keep: "Keep awake with lid closed", turnOff: "Turn off keep-awake", sleep: "Sleep now",
            batteryCaption: "Temporary, reverts under \(floor)%", acCaption: "On AC, no battery limit",
            settings: "Settings", notifications: "Show notifications", thermal: "Auto-sleep when hot", floor: "Battery floor",
            offBody: "Closing the lid sleeps the Mac as usual.", acBody: "Mac keeps running with the lid closed (on AC).",
            lowBody: "Battery too low, override refused, connect power.",
            batteryBody: "Mac stays awake with the lid closed on battery, Low Power Mode on. Reverts on lid open, low battery, or power.",
            failBody: "Could not enable keep-awake: pmset needs the passwordless-sudo step (see README). Nothing changed.",
            openBody: "Lid opened: battery override cleared, default sleep restored.",
            autoACBody: "On AC: night mode enabled automatically. Click the moon to disable.",
            revokedBody: "Battery below \(floor)%: override revoked, Mac will sleep with the lid closed.",
            hotPrefix: "Went to sleep due to overheating at", autoBatteryBody: "On battery: night mode off, the lid sleeps the Mac as usual.")
        }
    }
}

private enum Shell {
    static func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments; task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    static func pmset(_ args: [String], sudo: Bool = false) -> (Int32, String) {
        sudo ? run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + args) : run("/usr/bin/pmset", args)
    }
}

private final class RuntimeState {
    private let d = UserDefaults.standard
    var batteryOverride: Bool { get { d.bool(forKey: "batteryOverride") } set { d.set(newValue, forKey: "batteryOverride") } }
    var manualOff: Bool { get { d.bool(forKey: "manualOff") } set { d.set(newValue, forKey: "manualOff") } }
    var priorLid: LidState {
        get { LidState(raw: d.string(forKey: "priorLid")) }
        set { d.set(newValue.raw, forKey: "priorLid") }
    }
    var lastTick: Date? { get { d.object(forKey: "lastTick") as? Date } set { d.set(newValue, forKey: "lastTick") } }
    var bootTime: String? { get { d.string(forKey: "bootTime") } set { d.set(newValue, forKey: "bootTime") } }
}

private extension LidState {
    init(raw: String?) { self = raw == "closed" ? .closed : raw == "open" ? .open : .unknown }
    var raw: String { self == .closed ? "closed" : self == .open ? "open" : "unknown" }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let state = RuntimeState()
    private var timer: Timer?
    private var permissionAlertShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["notifications": true, "thermalGuard": true, "batteryFloor": 20])
        status.menu = NSMenu(); status.menu?.delegate = self
        requestNotificationsIfNeeded()
        registerLoginItem()
        reconcileBoot()
        refreshMenu()
        guardTick()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.guardTick() }
        }
        if !hasSudoRule() { showSudoFix() }
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private var floor: Int { UserDefaults.standard.integer(forKey: "batteryFloor") }
    private var copy: Copy { Copy.current(floor: floor) }

    private func snapshot() -> MachineSnapshot {
        let now = Date(), elapsed = state.lastTick.map { now.timeIntervalSince($0) } ?? 0
        return MachineSnapshot(power: powerSource(), batteryPercent: batteryPercent(), sleepDisabled: sleepDisabled(),
            batteryOverride: state.batteryOverride, manualOff: state.manualOff, lid: lidState(), previousLid: state.priorLid,
            secondsSinceLastTick: elapsed, thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            thermalGuard: UserDefaults.standard.bool(forKey: "thermalGuard"), batteryFloor: floor)
    }

    private func guardTick() {
        let s = snapshot()
        execute(StateMachine.guardTick(s))
        state.priorLid = s.lid; state.lastTick = Date()
        refreshMenu()
    }

    @objc private func toggle() { execute(StateMachine.toggle(snapshot())); refreshMenu() }
    @objc private func sleepNow() { _ = Shell.pmset(["sleepnow"], sudo: true) }
    @objc private func toggleNotifications() {
        let d = UserDefaults.standard, value = !d.bool(forKey: "notifications"); d.set(value, forKey: "notifications")
        if value { requestNotificationsIfNeeded() }; refreshMenu()
    }
    @objc private func toggleThermal() {
        let d = UserDefaults.standard; d.set(!d.bool(forKey: "thermalGuard"), forKey: "thermalGuard"); refreshMenu()
    }
    @objc private func setFloor(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.tag, forKey: "batteryFloor"); refreshMenu() }

    private func execute(_ decision: Decision) {
        for effect in decision.effects {
            switch effect {
            case let .setSleepDisabled(value, verify):
                _ = Shell.pmset(["-a", "disablesleep", value ? "1" : "0"], sudo: true)
                if verify && sleepDisabled() != value {
                    appendLog(value ? "auto-ON FAILED (pmset)" : "REVERT-VERIFY FAILED (SleepDisabled still 1)")
                    if value { send(.failure); showSudoFix(); return }
                }
            case let .setLowPowerMode(value): _ = Shell.pmset(["-b", "lowpowermode", value ? "1" : "0"], sudo: true)
            case let .setBatteryOverride(value): state.batteryOverride = value
            case let .setManualOff(value): state.manualOff = value
            case let .notify(kind): send(kind)
            case let .log(message): appendLog(message)
            case .thermalHistory: appendThermalHistory()
            case .sleepNow: _ = Shell.pmset(["sleepnow"], sudo: true)
            }
        }
    }

    private func refreshMenu() {
        let s = snapshot(), c = copy, menu = status.menu ?? NSMenu()
        menu.removeAllItems()
        status.button?.image = NSImage(systemSymbolName: (s.batteryOverride || s.sleepDisabled) ? "cup.and.saucer.fill" : "moon.zzz.fill", accessibilityDescription: "lid-awake")
        status.button?.image?.isTemplate = true

        add(c: s.batteryOverride || s.sleepDisabled ? c.awake : c.sleeps,
            image: s.batteryOverride || s.sleepDisabled ? "cup.and.saucer.fill" : "moon.zzz.fill", enabled: false, to: menu)
        add(c: s.power == .ac ? c.ac : "\(c.battery) \(s.batteryPercent.map(String.init) ?? "?")%", enabled: false, to: menu)
        if s.batteryOverride { add(c: c.reverts, enabled: false, to: menu) }
        menu.addItem(.separator())
        if s.sleepDisabled { add(c: c.turnOff, image: "moon.zzz.fill", action: #selector(toggle), to: menu) }
        else {
            add(c: c.keep, image: "cup.and.saucer.fill", action: #selector(toggle), to: menu)
            add(c: s.power == .ac ? c.acCaption : c.batteryCaption, enabled: false, to: menu)
        }
        add(c: c.sleep, image: "zzz", action: #selector(sleepNow), to: menu)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: c.settings, action: nil, keyEquivalent: "")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        let submenu = NSMenu()
        let ni = add(c: c.notifications, action: #selector(toggleNotifications), to: submenu); ni.state = UserDefaults.standard.bool(forKey: "notifications") ? .on : .off
        let ti = add(c: c.thermal, action: #selector(toggleThermal), to: submenu); ti.state = UserDefaults.standard.bool(forKey: "thermalGuard") ? .on : .off
        let floorItem = NSMenuItem(title: "\(c.floor): \(floor)%", action: nil, keyEquivalent: "")
        floorItem.image = NSImage(systemSymbolName: "battery.25", accessibilityDescription: nil)
        let floors = NSMenu()
        for value in [10, 15, 20, 25, 30] {
            let item = NSMenuItem(title: "\(value)%", action: #selector(setFloor(_:)), keyEquivalent: "")
            item.target = self; item.tag = value; item.state = value == floor ? .on : .off; floors.addItem(item)
        }
        floorItem.submenu = floors; submenu.addItem(floorItem); settings.submenu = submenu; menu.addItem(settings)
        status.menu = menu
    }

    @discardableResult private func add(c title: String, image: String? = nil, action: Selector? = nil,
                                        enabled: Bool = true, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled
        if let image { item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil) }
        menu.addItem(item); return item
    }

    private func sleepDisabled() -> Bool {
        let output = Shell.pmset(["-g"]).1
        guard let line = output.split(separator: "\n").first(where: { $0.contains("SleepDisabled") }) else { return false }
        return line.split(whereSeparator: \.isWhitespace).last == "1"
    }
    private func powerSource() -> PowerSource { Shell.pmset(["-g", "ps"]).1.contains("AC Power") ? .ac : .battery }
    private func batteryPercent() -> Int? {
        let text = Shell.pmset(["-g", "batt"]).1
        guard let range = text.range(of: #"[0-9]+%"#, options: .regularExpression) else { return nil }
        return Int(text[range].dropLast())
    }
    private func lidState() -> LidState {
        let text = Shell.run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "1"]).1
        if text.contains("AppleClamshellState\" = Yes") { return .closed }
        if text.contains("AppleClamshellState\" = No") { return .open }
        return .unknown
    }

    private func send(_ kind: Notice) {
        guard UserDefaults.standard.bool(forKey: "notifications") else { return }
        let c = copy, body: String
        switch kind {
        case .off: body = c.offBody; case .acOn: body = c.acBody; case .lowRefusal: body = c.lowBody
        case .batteryOn: body = c.batteryBody; case .failure: body = c.failBody; case .lidOpened: body = c.openBody
        case .acAutoOn: body = c.autoACBody; case .lowRevoked: body = c.revokedBody
        case .hot: body = "\(c.hotPrefix) \(thermalTimestamp())"; case .batteryAutoOff: body = c.autoBatteryBody
        }
        let content = UNMutableNotificationContent(); content.title = "lid-awake"; content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    private func requestNotificationsIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "notifications") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func thermalTimestamp() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "h:mma 'on' EEEE, d MMM"
        return f.string(from: Date()).replacingOccurrences(of: "AM", with: "am").replacingOccurrences(of: "PM", with: "pm")
    }
    private func stateDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lid-awake/state", isDirectory: true)
    }
    private func appendLog(_ message: String) { append("\(stamp()) \(message)\n", to: "lid-guard.log") }
    private func appendThermalHistory() { append("\(copy.hotPrefix) \(thermalTimestamp())\n", to: "thermal-history.txt") }
    private func append(_ text: String, to name: String) {
        let dir = stateDirectory(); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        if let handle = try? FileHandle(forWritingTo: url) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(text.utf8)); try? handle.close() }
        else { try? Data(text.utf8).write(to: url) }
    }
    private func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.string(from: Date()) }

    private func reconcileBoot() {
        let boot = Shell.run("/usr/sbin/sysctl", ["-n", "kern.boottime"]).1
        if let old = state.bootTime, old != boot {
            if state.batteryOverride { _ = Shell.pmset(["-b", "lowpowermode", "0"], sudo: true) }
            state.batteryOverride = false; state.manualOff = false; state.priorLid = .unknown; state.lastTick = nil
        }
        state.bootTime = boot
    }
    private func hasSudoRule() -> Bool { Shell.pmset(["-g"], sudo: true).0 == 0 }
    private func showSudoFix() {
        guard !permissionAlertShown else { return }; permissionAlertShown = true
        let user = NSUserName(), line = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset"
        let alert = NSAlert(); alert.messageText = "lid-awake needs permission to run pmset"
        alert.informativeText = "Run: sudo visudo -f /etc/sudoers.d/lid-awake\nThen add this line:\n\(line)"
        alert.addButton(withTitle: "Copy fix"); alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(line, forType: .string) }
    }
    private func registerLoginItem() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() } catch { appendLog("login item registration failed: \(error.localizedDescription)") }
    }
}

@main
struct LidAwakeApp {
    static func main() {
        let app = NSApplication.shared, delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
    }
}
