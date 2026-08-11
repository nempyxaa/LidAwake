import AppKit
import Darwin
import Foundation
import ServiceManagement
import UserNotifications

private struct Copy {
    let sleeps, awake, battery, ac, reverts: String
    let keep, turnOff, sleep, batteryCaption, acCaption: String
    let settings, notifications, thermal, floor: String
    let batteryModeHeader, modeLid, modeFloor, modeAsk: String
    let untilLid, untilFloor, awakeUntilLid, awakeUntilFloor: String
    let offBody, acBody, lowBody, batteryBody, failBody: String
    let openBody, autoACBody, revokedBody, hotPrefix, autoBatteryBody, revertFailBody: String

    static func current(floor: Int) -> Copy {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        switch language {
        case "de": return Copy(
            sleeps: "Deckel zu: Ruhezustand", awake: "Deckel zu: bleibt wach", battery: "Akku:", ac: "Strom: Netz",
            reverts: "Endet bei: Deckel auf, unter \(floor)%, oder am Netz",
            keep: "Mit geschlossenem Deckel wach halten", turnOff: "Wachhalten ausschalten", sleep: "Jetzt in den Ruhezustand",
            batteryCaption: "Vorübergehend, endet unter \(floor)%", acCaption: "Am Netz, kein Akkulimit",
            settings: "Einstellungen", notifications: "Mitteilungen anzeigen", thermal: "Bei Hitze automatisch schlafen", floor: "Akku-Mindeststand",
            batteryModeHeader: "Im Akkubetrieb wach bleiben bis", modeLid: "Deckel geöffnet wird", modeFloor: "Akkugrenze oder Überhitzung", modeAsk: "Jedes Mal fragen",
            untilLid: "Bis der Deckel geöffnet wird", untilFloor: "Bis Akkugrenze oder Überhitzung", awakeUntilLid: "Wach bis: Deckel", awakeUntilFloor: "Wach bis: Akkugrenze/Hitze",
            offBody: "Deckel schließen versetzt den Mac wie gewohnt in den Ruhezustand.", acBody: "Der Mac läuft mit geschlossenem Deckel weiter (am Netz).",
            lowBody: "Akku zu niedrig, Wachhalten abgelehnt, Netzteil anschliessen.",
            batteryBody: "Mac bleibt mit geschlossenem Deckel im Akkubetrieb wach, Stromsparmodus an. Endet bei Deckel auf, wenig Akku oder Netz.",
            failBody: "Konnte Wachhalten nicht aktivieren: pmset braucht die passwortlose sudo-Regel (siehe README). Nichts geaendert.",
            openBody: "Deckel offen: Akku-Uebersteuerung beendet, Standard-Ruhezustand wieder aktiv.",
            autoACBody: "Am Netz: Nachtmodus automatisch an. Zum Ausschalten den Mond anklicken.",
            revokedBody: "Akku unter \(floor)%: Uebersteuerung beendet, Mac schlaeft bei geschlossenem Deckel.",
            hotPrefix: "Ruhezustand wegen Ueberhitzung um", autoBatteryBody: "Im Akkubetrieb: Nachtmodus aus, Deckel schliessen versetzt in den Ruhezustand.", revertFailBody: "Ruhezustand konnte nicht wiederhergestellt werden. lid-awake versucht es in 60 Sekunden erneut.")
        case "fr": return Copy(
            sleeps: "Capot fermé : veille", awake: "Capot fermé : reste actif", battery: "Batterie :", ac: "Alim. : secteur",
            reverts: "Fin si : capot ouvert, sous \(floor)%, ou secteur",
            keep: "Rester actif capot fermé", turnOff: "Désactiver le maintien actif", sleep: "Mettre en veille",
            batteryCaption: "Temporaire, fin sous \(floor)%", acCaption: "Sur secteur, sans limite de batterie",
            settings: "Réglages", notifications: "Afficher les notifications", thermal: "Veille auto en cas de surchauffe", floor: "Seuil de batterie",
            batteryModeHeader: "Sur batterie, rester actif jusqu'à", modeLid: "Ouverture du capot", modeFloor: "Seuil de batterie ou surchauffe", modeAsk: "Demander à chaque fois",
            untilLid: "Jusqu'à l'ouverture du capot", untilFloor: "Jusqu'au seuil de batterie ou à la surchauffe", awakeUntilLid: "Actif jusqu'à : capot", awakeUntilFloor: "Actif jusqu'à : seuil/chaleur",
            offBody: "Fermer le capot met le Mac en veille comme d'habitude.", acBody: "Le Mac continue capot ferme (sur secteur).",
            lowBody: "Batterie trop basse, maintien refuse, branchez l'alimentation.",
            batteryBody: "Le Mac reste actif capot ferme sur batterie, mode economie d'energie active. Fin si capot ouvert, batterie faible ou secteur.",
            failBody: "Activation impossible: pmset requiert la regle sudo sans mot de passe (voir README). Rien change.",
            openBody: "Capot ouvert: derogation batterie terminee, veille par defaut retablie.",
            autoACBody: "Sur secteur: mode nuit active automatiquement. Cliquez la lune pour desactiver.",
            revokedBody: "Batterie sous \(floor)%: derogation terminee, le Mac se met en veille capot ferme.",
            hotPrefix: "Mise en veille pour surchauffe a", autoBatteryBody: "Sur batterie: mode nuit desactive, fermer le capot met en veille.", revertFailBody: "Impossible de rétablir la veille. lid-awake réessaiera dans 60 secondes.")
        case "es": return Copy(
            sleeps: "Tapa cerrada: en reposo", awake: "Tapa cerrada: sigue activo", battery: "Batería:", ac: "Corriente: red",
            reverts: "Termina si: abres la tapa, bajo \(floor)%, o al enchufar",
            keep: "Mantener activo con la tapa cerrada", turnOff: "Desactivar mantener activo", sleep: "Poner en reposo",
            batteryCaption: "Temporal, termina bajo \(floor)%", acCaption: "Con corriente, sin límite de batería",
            settings: "Ajustes", notifications: "Mostrar notificaciones", thermal: "Reposo automático si se calienta", floor: "Umbral de batería",
            batteryModeHeader: "Con batería, mantener activo hasta", modeLid: "Abrir la tapa", modeFloor: "Umbral de batería o sobrecalentamiento", modeAsk: "Preguntar cada vez",
            untilLid: "Hasta abrir la tapa", untilFloor: "Hasta el umbral de batería o sobrecalentamiento", awakeUntilLid: "Activo hasta: tapa", awakeUntilFloor: "Activo hasta: umbral/calor",
            offBody: "Cerrar la tapa pone el Mac en reposo como siempre.", acBody: "El Mac sigue con la tapa cerrada (con corriente).",
            lowBody: "Bateria muy baja, se rechazo, conecta la corriente.",
            batteryBody: "El Mac sigue activo con la tapa cerrada en bateria, modo de bajo consumo activado. Termina al abrir, bateria baja o corriente.",
            failBody: "No se pudo activar: pmset necesita la regla sudo sin contrasena (ver README). Nada cambio.",
            openBody: "Tapa abierta: anulacion en bateria terminada, reposo por defecto restaurado.",
            autoACBody: "Con corriente: modo noche activado automaticamente. Haz clic en la luna para desactivar.",
            revokedBody: "Bateria bajo \(floor)%: anulacion terminada, el Mac entra en reposo con la tapa cerrada.",
            hotPrefix: "En reposo por sobrecalentamiento a las", autoBatteryBody: "En bateria: modo noche desactivado, cerrar la tapa pone en reposo.", revertFailBody: "No se pudo restaurar el reposo. lid-awake volverá a intentarlo en 60 segundos.")
        case "ru": return Copy(
            sleeps: "Крышка закрыта: сон", awake: "Крышка закрыта: не спит", battery: "Батарея:", ac: "Питание: сеть",
            reverts: "Вернётся: открыл крышку, ниже \(floor)%, или зарядка",
            keep: "Не спать с закрытой крышкой", turnOff: "Выключить «не спать»", sleep: "Уснуть сейчас",
            batteryCaption: "Временно, вернётся ниже \(floor)%", acCaption: "На зарядке, без лимита батареи",
            settings: "Настройки", notifications: "Показывать уведомления", thermal: "Засыпать при перегреве", floor: "Порог батареи",
            batteryModeHeader: "На батарее не спать до", modeLid: "Открытия крышки", modeFloor: "Порога батареи или перегрева", modeAsk: "Спрашивать каждый раз",
            untilLid: "До открытия крышки", untilFloor: "До порога батареи или перегрева", awakeUntilLid: "Не спит до: крышка", awakeUntilFloor: "Не спит до: порог/перегрев",
            offBody: "Крышка теперь усыпляет Mac как обычно.", acBody: "Mac продолжит работать с закрытой крышкой (на питании).",
            lowBody: "Батарея слишком низкая, оверрайд не включён, подключи питание.",
            batteryBody: "Mac не уснёт с закрытой крышкой на батарее, включён режим энергосбережения. Снимется само: открытие крышки, низкий заряд, или питание.",
            failBody: "Не удалось включить: pmset нужен беспарольный sudo (см. README). Ничего не изменилось.",
            openBody: "Крышка открыта: батарейный оверрайд снят, дефолт снова сон.",
            autoACBody: "На питании: ночной режим включён автоматически. Выключить - клик по луне.",
            revokedBody: "Батарея ниже \(floor)%: оверрайд снят, Mac уснёт с крышкой.",
            hotPrefix: "Ушёл в сон из-за перегрева в", autoBatteryBody: "На батарее: ночной режим выключен, крышка усыпляет как обычно.", revertFailBody: "Не удалось вернуть обычный сон. lid-awake повторит попытку через 60 секунд.")
        default: return Copy(
            sleeps: "Lid closed: sleeps", awake: "Lid closed: staying awake", battery: "Battery:", ac: "Power: AC",
            reverts: "Reverts on: lid open, under \(floor)%, plugged in",
            keep: "Keep awake with lid closed", turnOff: "Turn off keep-awake", sleep: "Sleep now",
            batteryCaption: "Temporary, reverts under \(floor)%", acCaption: "On AC, no battery limit",
            settings: "Settings", notifications: "Show notifications", thermal: "Auto-sleep when hot", floor: "Battery floor",
            batteryModeHeader: "On battery, keep awake until", modeLid: "Lid opens", modeFloor: "Battery floor or overheating", modeAsk: "Ask each time",
            untilLid: "Until lid opens", untilFloor: "Until battery floor or overheating", awakeUntilLid: "Awake until: lid", awakeUntilFloor: "Awake until: floor/heat",
            offBody: "Closing the lid sleeps the Mac as usual.", acBody: "Mac keeps running with the lid closed (on AC).",
            lowBody: "Battery too low, override refused, connect power.",
            batteryBody: "Mac stays awake with the lid closed on battery, Low Power Mode on. Reverts on lid open, low battery, or power.",
            failBody: "Could not enable keep-awake: pmset needs the passwordless-sudo step (see README). Nothing changed.",
            openBody: "Lid opened: battery override cleared, default sleep restored.",
            autoACBody: "On AC: night mode enabled automatically. Click the moon to disable.",
            revokedBody: "Battery below \(floor)%: override revoked, Mac will sleep with the lid closed.",
            hotPrefix: "Went to sleep due to overheating at", autoBatteryBody: "On battery: night mode off, the lid sleeps the Mac as usual.", revertFailBody: "Could not restore normal sleep. lid-awake will retry in 60 seconds.")
        }
    }
}

private struct UIStrings {
    let quit, moveTitle, moveBody, migrationTitle, migrationBody: String
    let permissionTitle, permissionBody, copyFix, ok: String
    static var current: UIStrings {
        switch Locale.current.language.languageCode?.identifier ?? "en" {
        case "de": return UIStrings(quit: "Beenden", moveTitle: "lid-awake nach Programme verschieben", moveBody: "Der Sicherheitsdienst und der Anmeldestart werden nur aus /Applications aktiviert. Verschiebe die App dorthin und öffne sie erneut.", migrationTitle: "Alte Version entfernt", migrationBody: "Der alte Hintergrunddienst und das SwiftBar-Plugin wurden entfernt.", permissionTitle: "lid-awake benötigt die Berechtigung für pmset", permissionBody: "Führe diesen Befehl aus: sudo visudo -f /etc/sudoers.d/lid-awake\nFüge dann diese Zeile ein:", copyFix: "Lösung kopieren", ok: "OK")
        case "fr": return UIStrings(quit: "Quitter", moveTitle: "Déplacez lid-awake dans Applications", moveBody: "Le service de sécurité et l'ouverture de session ne sont activés que depuis /Applications. Déplacez l'app, puis rouvrez-la.", migrationTitle: "Ancienne version supprimée", migrationBody: "L'ancien service en arrière-plan et le plugin SwiftBar ont été supprimés.", permissionTitle: "lid-awake a besoin d'accéder à pmset", permissionBody: "Exécutez : sudo visudo -f /etc/sudoers.d/lid-awake\nAjoutez ensuite cette ligne :", copyFix: "Copier le correctif", ok: "OK")
        case "es": return UIStrings(quit: "Salir", moveTitle: "Mueve lid-awake a Aplicaciones", moveBody: "El servicio de seguridad y el inicio de sesión solo se activan desde /Applications. Mueve la app allí y vuelve a abrirla.", migrationTitle: "Versión anterior eliminada", migrationBody: "Se eliminaron el servicio anterior y el plugin de SwiftBar.", permissionTitle: "lid-awake necesita permiso para usar pmset", permissionBody: "Ejecuta: sudo visudo -f /etc/sudoers.d/lid-awake\nDespués añade esta línea:", copyFix: "Copiar solución", ok: "Aceptar")
        case "ru": return UIStrings(quit: "Выйти", moveTitle: "Перемести lid-awake в Программы", moveBody: "Защитный агент и запуск при входе включаются только из /Applications. Перемести приложение туда и открой снова.", migrationTitle: "Старая версия удалена", migrationBody: "Старый фоновый агент и плагин SwiftBar удалены.", permissionTitle: "lid-awake нужен доступ к pmset", permissionBody: "Выполни: sudo visudo -f /etc/sudoers.d/lid-awake\nЗатем добавь строку:", copyFix: "Скопировать", ok: "ОК")
        default: return UIStrings(quit: "Quit", moveTitle: "Move lid-awake to Applications", moveBody: "The safety agent and login item are enabled only from /Applications. Move the app there, then open it again.", migrationTitle: "Old version removed", migrationBody: "The old background agent and SwiftBar plugin were removed.", permissionTitle: "lid-awake needs permission to run pmset", permissionBody: "Run: sudo visudo -f /etc/sudoers.d/lid-awake\nThen add this line:", copyFix: "Copy fix", ok: "OK")
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
    var batteryContract: BatteryContract? {
        get { d.object(forKey: "batteryContract").flatMap { ($0 as? NSNumber).flatMap { BatteryContract(rawValue: $0.intValue) } } }
        set {
            if let newValue { d.set(newValue.rawValue, forKey: "batteryContract") }
            else { d.removeObject(forKey: "batteryContract") }
        }
    }
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
    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let state = RuntimeState()
    private var timer: Timer?
    private var permissionAlertShown = false
    private var activity: NSObjectProtocol?
    private var headless = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.nempyxaa.lid-awake")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
        guard peers.isEmpty else { NSApp.terminate(nil); return }
        UserDefaults.standard.register(defaults: ["notifications": true, "thermalGuard": true, "batteryFloor": 20, "batteryMode": BatteryMode.lidOpens.rawValue])
        status.menu = NSMenu(); status.menu?.delegate = self
        requestNotificationsIfNeeded()
        configurePersistentServices()
        reconcileBoot()
        refreshMenu()
        guardTick()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.guardTick() }
        }
        timer?.tolerance = 5
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Keep lid-awake safety state fresh")
        if !hasSudoRule() { showSudoFix() }
    }

    func runGuardTickHeadless() {
        headless = true
        UserDefaults.standard.register(defaults: ["notifications": true, "thermalGuard": true, "batteryFloor": 20, "batteryMode": BatteryMode.lidOpens.rawValue])
        reconcileBoot(); guardTick(refresh: false)
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private var floor: Int { UserDefaults.standard.integer(forKey: "batteryFloor") }
    private var batteryMode: BatteryMode { BatteryMode(rawValue: UserDefaults.standard.integer(forKey: "batteryMode")) ?? .lidOpens }
    private var copy: Copy { Copy.current(floor: floor) }

    private func snapshot() -> MachineSnapshot {
        let now = Date(), elapsed = state.lastTick.map { now.timeIntervalSince($0) } ?? 0
        return MachineSnapshot(power: powerSource(), batteryPercent: batteryPercent(), sleepDisabled: sleepDisabled(),
            batteryOverride: state.batteryOverride, manualOff: state.manualOff, lid: lidState(), previousLid: state.priorLid,
            secondsSinceLastTick: elapsed, thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            thermalGuard: UserDefaults.standard.bool(forKey: "thermalGuard"), batteryFloor: floor,
            batteryMode: batteryMode, batteryContract: state.batteryContract)
    }

    private func guardTick(refresh: Bool = true) {
        let s = snapshot()
        execute(StateMachine.guardTick(s))
        state.priorLid = s.lid; state.lastTick = Date()
        if refresh { refreshMenu() }
    }

    @objc private func toggle() { _ = execute(StateMachine.toggle(snapshot())); refreshMenu() }
    @objc private func armUntilLid() { armBatteryOverride(.lidOpens) }
    @objc private func armUntilFloor() { armBatteryOverride(.floorOrHeat) }
    private func armBatteryOverride(_ contract: BatteryContract) {
        _ = execute(StateMachine.toggle(snapshot(), armContract: contract)); refreshMenu()
    }
    @objc private func sleepNow() { _ = Shell.pmset(["sleepnow"], sudo: true) }
    @objc private func toggleNotifications() {
        let d = UserDefaults.standard, value = !d.bool(forKey: "notifications"); d.set(value, forKey: "notifications")
        if value { requestNotificationsIfNeeded() }; refreshMenu()
    }
    @objc private func toggleThermal() {
        let d = UserDefaults.standard; d.set(!d.bool(forKey: "thermalGuard"), forKey: "thermalGuard"); refreshMenu()
    }
    @objc private func setFloor(_ sender: NSMenuItem) { UserDefaults.standard.set(sender.tag, forKey: "batteryFloor"); refreshMenu() }
    @objc private func setBatteryMode(_ sender: NSMenuItem) {
        guard BatteryMode(rawValue: sender.tag) != nil else { return }
        UserDefaults.standard.set(sender.tag, forKey: "batteryMode"); refreshMenu()
    }

    @discardableResult private func execute(_ decision: Decision) -> Bool {
        for effect in decision.effects {
            switch effect {
            case let .setSleepDisabled(value, verify):
                _ = Shell.pmset(["-a", "disablesleep", value ? "1" : "0"], sudo: true)
                if verify && sleepDisabled() != value {
                    appendLog(value ? "auto-ON FAILED (pmset)" : "REVERT-VERIFY FAILED (SleepDisabled still 1)")
                    send(value ? .failure : .revertFailure); showSudoFix(); return false
                }
            case let .setLowPowerMode(value): _ = Shell.pmset(["-b", "lowpowermode", value ? "1" : "0"], sudo: true)
            case let .setBatteryOverride(value): state.batteryOverride = value
            case let .setBatteryContract(value): state.batteryContract = value
            case let .setManualOff(value): state.manualOff = value
            case let .notify(kind): send(kind)
            case let .log(message): appendLog(message)
            case .thermalHistory: appendThermalHistory()
            case .sleepNow: _ = Shell.pmset(["sleepnow"], sudo: true)
            }
        }
        return true
    }

    private func refreshMenu() {
        let s = snapshot(), c = copy, menu = status.menu ?? NSMenu()
        menu.removeAllItems()
        status.button?.image = NSImage(systemSymbolName: (s.batteryOverride || s.sleepDisabled) ? "cup.and.saucer.fill" : "moon.zzz.fill", accessibilityDescription: "lid-awake")
        status.button?.image?.isTemplate = true

        add(c: s.batteryOverride || s.sleepDisabled ? c.awake : c.sleeps,
            image: s.batteryOverride || s.sleepDisabled ? "cup.and.saucer.fill" : "moon.zzz.fill", enabled: false, to: menu)
        add(c: s.power == .ac ? c.ac : "\(c.battery) \(s.batteryPercent.map(String.init) ?? "?")%", enabled: false, to: menu)
        if s.batteryOverride {
            let contract = s.batteryMode == .lidOpens ? BatteryContract.lidOpens :
                s.batteryMode == .floorOrHeat ? BatteryContract.floorOrHeat : s.batteryContract
            add(c: contract == .floorOrHeat ? c.awakeUntilFloor : c.awakeUntilLid, enabled: false, to: menu)
        }
        menu.addItem(.separator())
        if s.sleepDisabled { add(c: c.turnOff, image: "moon.zzz.fill", action: #selector(toggle), to: menu) }
        else {
            if s.power == .battery && s.batteryMode == .askEachTime {
                let keep = add(c: c.keep, image: "cup.and.saucer.fill", to: menu)
                let choices = NSMenu()
                add(c: c.untilLid, action: #selector(armUntilLid), to: choices)
                add(c: c.untilFloor, action: #selector(armUntilFloor), to: choices)
                keep.submenu = choices
            } else {
                add(c: c.keep, image: "cup.and.saucer.fill", action: #selector(toggle), to: menu)
            }
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
        floorItem.submenu = floors; submenu.addItem(floorItem)
        submenu.addItem(.separator())
        let modeHeader = add(c: c.batteryModeHeader, enabled: false, to: submenu)
        modeHeader.attributedTitle = NSAttributedString(
            string: c.batteryModeHeader,
            attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)]
        )
        for (mode, title) in [(BatteryMode.lidOpens, c.modeLid), (.floorOrHeat, c.modeFloor), (.askEachTime, c.modeAsk)] {
            let item = add(c: title, action: #selector(setBatteryMode(_:)), to: submenu)
            item.tag = mode.rawValue; item.state = mode == batteryMode ? .on : .off
        }
        submenu.addItem(.separator())
        add(c: UIStrings.current.quit, action: #selector(quit), to: submenu)
        settings.submenu = submenu; menu.addItem(settings)
        status.menu = menu
    }

    @objc private func quit() {
        let cleanup = Decision(effects: [.setSleepDisabled(false, verify: true), .setLowPowerMode(false), .setBatteryOverride(false), .setBatteryContract(nil), .setManualOff(false)])
        guard execute(cleanup) else { return }
        unloadGuardAgent(removeFile: true)
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        NSApp.terminate(nil)
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
        case .revertFailure: body = c.revertFailBody
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
            state.batteryOverride = false; state.batteryContract = nil; state.manualOff = false; state.priorLid = .unknown; state.lastTick = nil
        }
        state.bootTime = boot
    }
    private var sudoersLine: String {
        "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -b lowpowermode 0, /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset sleepnow"
    }
    private func hasSudoRule() -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]).0 == 0
    }
    private func showSudoFix() {
        guard !headless else { return }
        guard !permissionAlertShown else { return }; permissionAlertShown = true
        let c = UIStrings.current, alert = NSAlert(); alert.messageText = c.permissionTitle
        alert.informativeText = "\(c.permissionBody)\n\(sudoersLine)"
        alert.addButton(withTitle: c.copyFix); alert.addButton(withTitle: c.ok)
        if alert.runModal() == .alertFirstButtonReturn { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sudoersLine, forType: .string) }
    }
    private func registerLoginItem() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() } catch { appendLog("login item registration failed: \(error.localizedDescription)") }
    }

    private var runsFromApplications: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }
    private var guardPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.nempyxaa.lid-awake.guard.plist")
    }
    private func configurePersistentServices() {
        guard runsFromApplications else {
            let c = UIStrings.current, alert = NSAlert(); alert.messageText = c.moveTitle; alert.informativeText = c.moveBody
            alert.addButton(withTitle: c.ok); alert.runModal(); appendLog("persistent services refused outside /Applications"); return
        }
        migrateLegacyInstall()
        installGuardAgent(); registerLoginItem()
    }
    private func installGuardAgent() {
        let executable = Bundle.main.executableURL?.path ?? ""
        let plist: [String: Any] = ["Label": "com.nempyxaa.lid-awake.guard", "ProgramArguments": [executable, "--guard-tick"], "StartInterval": 60]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: guardPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: guardPlistURL, options: .atomic)
            let domain = "gui/\(getuid())"
            _ = Shell.run("/bin/launchctl", ["bootout", domain + "/com.nempyxaa.lid-awake.guard"])
            let result = Shell.run("/bin/launchctl", ["bootstrap", domain, guardPlistURL.path])
            if result.0 != 0 { appendLog("guard LaunchAgent bootstrap failed") }
        } catch { appendLog("guard LaunchAgent install failed: \(error.localizedDescription)") }
    }
    private func unloadGuardAgent(removeFile: Bool) {
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/com.nempyxaa.lid-awake.guard"])
        if removeFile { try? FileManager.default.removeItem(at: guardPlistURL) }
    }
    private func migrateLegacyInstall() {
        guard !UserDefaults.standard.bool(forKey: "nativeMigrationCompleted") else { return }
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let oldPlist = home.appendingPathComponent("Library/LaunchAgents/org.lidawake.guard.plist")
        var removed = false
        if fm.fileExists(atPath: oldPlist.path) {
            _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", oldPlist.path])
            try? fm.removeItem(at: oldPlist); removed = true
        }
        let pluginDirectory = Shell.run("/usr/bin/defaults", ["read", "com.ameba.SwiftBar", "PluginDirectory"]).1
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !pluginDirectory.isEmpty {
            let plugin = URL(fileURLWithPath: pluginDirectory).appendingPathComponent("lidawake.10s.sh")
            if fm.fileExists(atPath: plugin.path) { try? fm.removeItem(at: plugin); removed = true }
        }
        UserDefaults.standard.set(true, forKey: "nativeMigrationCompleted")
        if removed {
            let c = UIStrings.current, alert = NSAlert(); alert.messageText = c.migrationTitle; alert.informativeText = c.migrationBody
            alert.addButton(withTitle: c.ok); alert.runModal()
        }
    }
}

@main
@MainActor
struct LidAwakeApp {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--guard-tick") {
            let delegate = AppDelegate(); delegate.runGuardTickHeadless(); return
        }
        let app = NSApplication.shared, delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
    }
}
