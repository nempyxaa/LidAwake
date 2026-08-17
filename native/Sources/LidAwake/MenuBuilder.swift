import AppKit
import LidAwakeCore

@MainActor
extension AppDelegate {
// MARK: Menu

func refreshMenu() {
    guard !headless else { return }
    let s = snapshot(), menu = status.menu ?? NSMenu()
    menu.removeAllItems()
    if let image = icon(for: s) {
        status.button?.image = image
        status.button?.title = ""
    } else {
        // Never an imageless, titleless status item — the v2 regression.
        status.button?.image = nil
        status.button?.title = V3Strings.iconFallback
    }

    if let line = state.postmortem { add(line, enabled: false, to: menu) }

    if s.power == .ac {
        if s.oneShotActive { buildACHoldMenu(s, menu) } else { buildACIdleMenu(s, menu) }
    } else if s.mode == .always {
        if s.alwaysPaused { buildAlwaysPausedMenu(s, menu) } else { buildAlwaysActiveMenu(s, menu) }
    } else if s.oneShotActive {
        buildOneShotArmedMenu(s, menu)
    } else {
        buildIdleMenu(s, menu)
    }

    menu.addItem(.separator())
    menu.addItem(settingsItem(s))
    status.menu = menu
}

private func buildIdleMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
    add(V3Strings.idleHeader, image: "moon.zzz.fill", enabled: false, to: menu)
    add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
    menu.addItem(.separator())
    // Spec: arming is disabled only at/below the floor, while hot, or with
    // no readable battery (J-11); the resume predicate gates resumption,
    // not arming.
    let unavailable = StateMachine.batteryUnavailable(s.batteryPercent)
    let floorHit = StateMachine.floorHit(percent: s.batteryPercent, floor: s.batteryFloor)
    let hot = s.thermalState >= StateMachine.seriousThermal
    let ready = !unavailable && !floorHit && !hot
    let arm = add(V3Strings.armItem, image: "cup.and.saucer.fill",
                  action: ready ? #selector(armClicked) : nil, enabled: ready, to: menu)
    let contract = s.mode == .ignoringLid
        ? V3Strings.armSubIgnoringLid(s.batteryFloor)
        : V3Strings.armSubUntilLid(s.batteryFloor)
    if ready {
        arm.subtitle = contract + "\n" + V3Strings.armSubChangeMode
    } else if unavailable {
        // Its own stated reason — never presented as a floor hit (J-11).
        arm.subtitle = V3Strings.armDisabledNoBattery
    } else {
        // Disabled with the reason as the subtitle.
        arm.subtitle = floorHit ? V3Strings.armDisabledLow(s.batteryFloor) : V3Strings.armDisabledHot
    }
    add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
}

private func buildOneShotArmedMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
    add(V3Strings.oneShotHeader, image: "cup.and.saucer.fill", enabled: false, to: menu)
    add(s.mode == .ignoringLid ? V3Strings.untilOneShotIgnoringLid(s.batteryFloor)
                               : V3Strings.untilOneShotLid(s.batteryFloor),
        enabled: false, to: menu)
    add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
    menu.addItem(.separator())
    add(V3Strings.turnOff, image: "moon.zzz.fill", action: #selector(turnOffClicked), to: menu)
    let sleep = add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
    sleep.subtitle = V3Strings.sleepNowSubOneShot
}

private func buildAlwaysActiveMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
    add(V3Strings.alwaysHeader, image: "cup.and.saucer.fill", enabled: false, to: menu)
    add(V3Strings.alwaysUntil(s.batteryFloor), enabled: false, to: menu)
    add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
    menu.addItem(.separator())
    if s.skipOnce {
        add(V3Strings.skipOnceArmedItem, image: "moon.zzz.fill", action: #selector(skipOnceClicked), to: menu)
    } else {
        let skip = add(V3Strings.skipOnceItem, image: "moon.zzz.fill", action: #selector(skipOnceClicked), to: menu)
        skip.subtitle = V3Strings.skipOnceSub
    }
    let off = add(V3Strings.turnOffAlwaysItem, action: #selector(turnOffAlwaysClicked), to: menu)
    off.subtitle = V3Strings.turnOffAlwaysSub
    add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
}

private func buildAlwaysPausedMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
    add(V3Strings.idleHeader, image: "moon.zzz.fill", enabled: false, to: menu)
    // The cooling line shows only when thermals are the actual blocker.
    add(StateMachine.pauseBlockedByHeatOnly(s) ? V3Strings.pausedHot
                                               : V3Strings.pausedFloor(s.batteryFloor),
        enabled: false, to: menu)
    add(V3Strings.battery(s.batteryPercent), enabled: false, to: menu)
    menu.addItem(.separator())
    let off = add(V3Strings.turnOffAlwaysItem, action: #selector(turnOffAlwaysClicked), to: menu)
    off.subtitle = V3Strings.turnOffAlwaysSub
    add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
}

private func buildACIdleMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
    add(s.acDeclined ? V3Strings.acHeaderDeclined : V3Strings.acHeaderOn,
        image: s.acDeclined ? "moon.zzz.fill" : "cup.and.saucer.fill", enabled: false, to: menu)
    add(V3Strings.batteryCharging(s.batteryPercent), enabled: false, to: menu)
    menu.addItem(.separator())
    let arm = add(V3Strings.armItem, image: "cup.and.saucer.fill",
                  action: s.acDeclined ? #selector(armClicked) : nil,
                  enabled: s.acDeclined, to: menu)
    arm.subtitle = V3Strings.armSubOnPower
    if !s.acDeclined {
        // The moon: clicking it declines automatic on-power Keep awake.
        // The decline is standing (until re-enabled on power; it dies at
        // reboot) — the subtitle says so (D2).
        let moon = add(V3Strings.turnOff, image: "moon.zzz.fill", action: #selector(declineClicked), to: menu)
        moon.subtitle = V3Strings.turnOffOnPowerSub
    }
    add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
}

private func buildACHoldMenu(_ s: MachineSnapshot, _ menu: NSMenu) {
    add(V3Strings.acHoldHeader, image: "bolt.fill", enabled: false, to: menu)
    add(s.mode == .ignoringLid ? V3Strings.untilOneShotIgnoringLid(s.batteryFloor)
                               : V3Strings.untilOneShotLid(s.batteryFloor),
        enabled: false, to: menu)
    add(V3Strings.batteryCharging(s.batteryPercent), enabled: false, to: menu)
    menu.addItem(.separator())
    add(V3Strings.turnOff, image: "moon.zzz.fill", action: #selector(turnOffClicked), to: menu)
    add(V3Strings.sleepNow, image: "zzz", action: #selector(sleepNowClicked), to: menu)
}

private func settingsItem(_ s: MachineSnapshot) -> NSMenuItem {
    let settings = NSMenuItem(title: V3Strings.settings, action: nil, keyEquivalent: "")
    settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    let submenu = NSMenu()

    let notifications = add(V3Strings.showNotifications, action: #selector(toggleNotifications), to: submenu)
    notifications.state = UserDefaults.standard.bool(forKey: "notifications") ? .on : .off

    let floorItem = NSMenuItem(title: V3Strings.floorItem(floor), action: nil, keyEquivalent: "")
    floorItem.image = NSImage(systemSymbolName: "battery.25", accessibilityDescription: nil)
    let floors = NSMenu()
    let keepAwakeLive = s.power == .battery &&
        (s.oneShotActive || (s.mode == .always && !s.alwaysPaused))
    for value in [10, 15, 20, 25, 30] {
        let endsCurrent = keepAwakeLive && (s.batteryPercent ?? 0) <= value
        let item = NSMenuItem(title: endsCurrent ? V3Strings.floorOptionEndsCurrent(value)
                                                                    : V3Strings.floorOption(value),
                              action: #selector(setFloor(_:)), keyEquivalent: "")
        item.target = self; item.tag = value; item.state = value == floor ? .on : .off
        floors.addItem(item)
    }
    floorItem.submenu = floors; submenu.addItem(floorItem)

    submenu.addItem(.separator())
    let header = add(V3Strings.modeSection, enabled: false, to: submenu)
    header.attributedTitle = NSAttributedString(
        string: V3Strings.modeSection,
        attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)])
    let lpm = add(V3Strings.lpmSetting, action: #selector(toggleLowPowerModeSetting), to: submenu)
    lpm.subtitle = V3Strings.lpmSettingSubtitle
    lpm.state = UserDefaults.standard.bool(forKey: "useLowPowerMode") ? .on : .off
    let radios: [(BatteryMode, String)] = [
        (.untilLidFloorHot, V3Strings.modeRadioUntilLid(floor)),
        (.ignoringLid, V3Strings.modeRadioIgnoringLid(floor)),
        (.always, V3Strings.modeRadioAlways(floor)),
    ]
    for (radioMode, title) in radios {
        let item = add(title, action: #selector(setBatteryMode(_:)), to: submenu)
        item.tag = radioMode.rawValue
        item.state = radioMode == mode ? .on : .off
    }
    submenu.addItem(.separator())
    add(V3Strings.about, action: #selector(showAbout), to: submenu)
    add(V3Strings.quit, action: #selector(quit), to: submenu)
    settings.submenu = submenu
    return settings
}

@objc private func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
}

@discardableResult private func add(_ title: String, image: String? = nil, action: Selector? = nil,
                                    enabled: Bool = true, to menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self; item.isEnabled = enabled
    if let image { item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil) }
    menu.addItem(item); return item
}

// Template icon states: outline = next close sleeps, filled = next close
// Keep awake, filled with a slash = selected but paused.
private func icon(for s: MachineSnapshot) -> NSImage? {
    let paused = s.power == .battery && s.mode == .always && s.alwaysPaused
    let awakeOnClose: Bool
    if s.power == .ac {
        awakeOnClose = !s.acDeclined || s.oneShotActive
    } else if s.mode == .always {
        awakeOnClose = !s.alwaysPaused && !s.skipOnce
    } else {
        awakeOnClose = s.oneShotActive
    }
    let base = NSImage(systemSymbolName: awakeOnClose || paused ? "cup.and.saucer.fill" : "cup.and.saucer",
                       accessibilityDescription: V3Strings.appName)
    guard paused, let filled = base else { base?.isTemplate = true; return base }
    let size = filled.size
    let slashed = NSImage(size: size, flipped: false) { rect in
        filled.draw(in: rect)
        // On a template image only the alpha channel matters: a stroked
        // slash over the opaque glyph is invisible. Knock a wide gap out
        // of the glyph with .destinationOut, then draw the slash inside
        // the gap so it reads as a line in light, dark, and contrast.
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
        path.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            path.lineWidth = 3.5
            NSColor.black.setStroke()
            path.stroke()
            ctx.restoreGState()
        }
        path.lineWidth = 1.5
        NSColor.black.setStroke()
        path.stroke()
        return true
    }
    slashed.isTemplate = true
    return slashed
}
}
