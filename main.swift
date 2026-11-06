import Cocoa
import ServiceManagement
import SwiftUI
import Security

// Claude usage in the menu bar. Reads the local Claude Code transcripts
// (~/.claude/projects/**/*.jsonl): nothing is sent anywhere, no login needed.

struct Rec { let ts: Date; let model: String; let inp: Int; let out: Int; let cw: Int; let cr: Int
    /// What a rate limit is measured on here: everything except cheap cache reads.
    var counted: Int { inp + out + cw }
    var total: Int { inp + out + cw + cr } }

struct Totals { var msgs = 0, inp = 0, out = 0, cw = 0, cr = 0
    var counted: Int { inp + out + cw }
    var total: Int { inp + out + cw + cr }
    mutating func add(_ r: Rec) { msgs += 1; inp += r.inp; out += r.out; cw += r.cw; cr += r.cr } }

let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
let isoPlain = ISO8601DateFormatter()

func compact(_ n: Int) -> String {
    let d = Double(n)
    if d >= 1e9 { return String(format: "%.2fB", d / 1e9) }
    if d >= 1e6 { return String(format: d >= 1e7 ? "%.1fM" : "%.2fM", d / 1e6) }
    if d >= 1e3 { return String(format: d >= 1e4 ? "%.0fk" : "%.1fk", d / 1e3) }
    return "\(n)"
}
func parseCount(_ s: String) -> Int? {
    var t = s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: "")
    var mult = 1.0
    if t.hasSuffix("k") { mult = 1e3; t.removeLast() } else if t.hasSuffix("m") { mult = 1e6; t.removeLast() } else if t.hasSuffix("b") { mult = 1e9; t.removeLast() }
    guard let v = Double(t), v > 0 else { return nil }
    return Int(v * mult)
}
func prettyModel(_ id: String) -> String {
    let parts = id.lowercased().replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
    guard let fam = parts.first(where: { ["opus", "sonnet", "haiku", "fable"].contains($0) }) else { return id }
    let ver = parts.filter { $0 != fam && Int($0) != nil && $0.count < 4 }.joined(separator: ".")
    return fam.capitalized + (ver.isEmpty ? "" : " " + ver)
}

final class TranscriptScanner {
    private var cache: [String: (mtime: Date, size: Int, recs: [(String, Rec)])] = [:]
    func scan() -> [Rec] {
        let root = NSHomeDirectory() + "/.claude/projects"
        var live = Set<String>()
        if let en = FileManager.default.enumerator(atPath: root) {
            for case let rel as String in en where rel.hasSuffix(".jsonl") {
                let path = root + "/" + rel; live.insert(path)
                guard let at = try? FileManager.default.attributesOfItem(atPath: path),
                      let m = at[.modificationDate] as? Date, let sz = at[.size] as? Int else { continue }
                if let c = cache[path], c.mtime == m, c.size == sz { continue }
                cache[path] = (m, sz, parse(path))
            }
        }
        for k in cache.keys where !live.contains(k) { cache.removeValue(forKey: k) }
        var seen: [String: Rec] = [:]   // resumed sessions repeat messages: count each once
        for (_, v) in cache { for (k, r) in v.recs { seen[k] = r } }
        return Array(seen.values)
    }
    private func parse(_ path: String) -> [(String, Rec)] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return [] }
        var out: [(String, Rec)] = []
        let needle = Array("\"usage\"".utf8)
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let p = buf.bindMemory(to: UInt8.self); let n = p.count; var start = 0
            while start < n {
                var end = start
                while end < n && p[end] != 10 { end += 1 }
                if end > start, memmem(p.baseAddress! + start, end - start, needle, needle.count) != nil,
                   let obj = try? JSONSerialization.jsonObject(with: Data(bytes: p.baseAddress! + start, count: end - start)) as? [String: Any],
                   let msg = obj["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
                   let model = msg["model"] as? String, !model.hasPrefix("<"),
                   let tss = obj["timestamp"] as? String, let ts = isoFrac.date(from: tss) ?? isoPlain.date(from: tss) {
                    let key = ((msg["id"] as? String) ?? (obj["uuid"] as? String) ?? "\(path):\(start)") + ":" + ((obj["requestId"] as? String) ?? "")
                    func i(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
                    out.append((key, Rec(ts: ts, model: model, inp: i("input_tokens"), out: i("output_tokens"),
                                         cw: i("cache_creation_input_tokens"), cr: i("cache_read_input_tokens"))))
                }
                start = end + 1
            }
        }
        return out
    }
}

struct Snapshot {
    var block: (start: Date, end: Date, used: Int)?
    var week = 0
    var byModel: [(String, Totals)] = []
    var all = Totals()
    var first: Date?
}

func snapshot(_ recs: [Rec], now: Date = Date()) -> Snapshot {
    var s = Snapshot()
    let sorted = recs.sorted { $0.ts < $1.ts }
    s.first = sorted.first?.ts
    var cur: (start: Date, end: Date, used: Int, last: Date)?
    let cal = Calendar.current
    for r in sorted {
        if cur == nil || r.ts >= cur!.end || r.ts.timeIntervalSince(cur!.last) >= 5 * 3600 {
            let hour = cal.dateInterval(of: .hour, for: r.ts)!.start   // a 5h window starts on the hour of its first message
            cur = (hour, hour.addingTimeInterval(5 * 3600), 0, r.ts)
        }
        cur!.used += r.counted; cur!.last = r.ts
    }
    if let c = cur, c.end > now { s.block = (c.start, c.end, c.used) }
    s.week = sorted.filter { $0.ts > now.addingTimeInterval(-7 * 86400) }.reduce(0) { $0 + $1.counted }
    var m: [String: Totals] = [:]
    for r in sorted { m[r.model, default: Totals()].add(r); s.all.add(r) }
    s.byModel = m.sorted { $0.value.total > $1.value.total }.map { ($0.key, $0.value) }
    return s
}


// ───────────────────────── exact limits from Claude (opt-in) ─────────────────────────

struct UsageRow: Identifiable { let id = UUID(); let label: String; let percent: Double?; let tokens: Int?; let resets: Date?; var caption: String? = nil }

enum ApiResult { case ok([UsageRow], String); case fail(String) }

/// Asks Claude's usage service for the real limits. Only runs when the user turns it on.
/// Reads the access token Claude Code already stores in the login keychain; it never refreshes
/// or writes it (refreshing would sign Claude Code out), and nothing is logged.
func fetchApi() -> ApiResult {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
                            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var out: CFTypeRef?
    let st = SecItemCopyMatching(q as CFDictionary, &out)
    guard st == errSecSuccess, let data = out as? Data else {
        return .fail(st == errSecItemNotFound ? "no Claude login found" : "access to your Claude login was not allowed")
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else { return .fail("login not readable") }
    if let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue, Date(timeIntervalSince1970: exp / 1000) < Date() {
        return .fail("login token expired: use Claude Code once to renew")
    }
    let plan = ((oauth["subscriptionType"] as? String) ?? "").uppercased()
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!); req.timeoutInterval = 10
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("ClaudeUsage/1.0", forHTTPHeaderField: "User-Agent")
    let sem = DispatchSemaphore(value: 0); var body: Data?; var code = 0
    URLSession.shared.dataTask(with: req) { d, r, _ in body = d; code = (r as? HTTPURLResponse)?.statusCode ?? 0; sem.signal() }.resume()
    _ = sem.wait(timeout: .now() + 12)
    guard code == 200, let b = body, let obj = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else {
        return .fail(code == 401 ? "login token rejected: use Claude Code once to renew" : "usage service unavailable (\(code))")
    }
    var rows: [(Int, UsageRow)] = []
    for (key, val) in obj {
        guard let d = val as? [String: Any], let util = (d["utilization"] as? NSNumber)?.doubleValue else { continue }
        var resets: Date?
        if let rs = d["resets_at"] as? String { resets = isoFrac.date(from: rs) ?? isoPlain.date(from: rs) }
        let label: String; let order: Int
        if key == "five_hour" { label = "Session (5h)"; order = 0 }
        else if key == "seven_day" { label = "Weekly (all models)"; order = 1 }
        else if key.hasPrefix("seven_day_") { label = "Weekly (" + prettyModel(String(key.dropFirst(10))) + ")"; order = 2 }
        else { continue }
        rows.append((order, UsageRow(label: label, percent: util, tokens: nil, resets: resets)))
    }
    if rows.isEmpty { return .fail("unexpected reply from the usage service") }
    return .ok(rows.sorted { ($0.0, $0.1.label) < ($1.0, $1.1.label) }.map { $0.1 }, plan)
}

// ───────────────────────── model + SwiftUI panel ─────────────────────────

final class UsageModel: ObservableObject {
    @Published var rows: [UsageRow] = []
    @Published var plan = ""
    @Published var source = "local"
    @Published var note: String?      // quiet hint
    @Published var warning: String?   // something went wrong (shown in orange)
    @Published var updated = Date()
    @Published var byModel: [(String, Totals)] = []
    @Published var all = Totals()
    @Published var first: Date?
    var badge: String {
        guard let r = rows.first else { return "…" }
        return r.percent.map { "\(Int($0.rounded()))%" } ?? compact(r.tokens ?? 0)
    }
}

func resetsText(_ d: Date) -> String {
    let left = Int(d.timeIntervalSinceNow)
    if left <= 0 { return "resetting now" }
    let f = DateFormatter()
    let days = left / 86400, h = (left % 86400) / 3600, m = (left % 3600) / 60
    if days >= 1 { f.dateFormat = "EEE HH:mm"; return "resets in \(days)d \(h)h (\(f.string(from: d)))" }
    f.dateFormat = "HH:mm"
    return h >= 1 ? "resets in \(h)h \(m)m (\(f.string(from: d)))" : "resets in \(m)m (\(f.string(from: d)))"
}

let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// A steady colour per model family, so a model keeps its colour as the list changes.
func modelColor(_ id: String) -> Color {
    let m = id.lowercased()
    if m.contains("opus") { return claudeOrange }
    if m.contains("sonnet") { return Color(red: 0.36, green: 0.55, blue: 0.72) }
    if m.contains("haiku") { return Color(red: 0.42, green: 0.65, blue: 0.54) }
    if m.contains("fable") { return Color(red: 0.56, green: 0.49, blue: 0.76) }
    return Color.gray
}

struct UsageBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(fraction >= 0.9 ? Color.red : claudeOrange).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }.frame(height: 6)
    }
}

struct PanelView: View {
    @ObservedObject var m: UsageModel
    let logo: NSImage?
    let onRefresh: () -> Void
    let onGear: () -> Void
    let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    let dfd: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let l = logo { Image(nsImage: l).resizable().frame(width: 28, height: 28) }
                else { Image(systemName: "chart.bar.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(claudeOrange).frame(width: 28, height: 28) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage").font(.system(size: 15, weight: .semibold))
                    Text(m.plan.isEmpty ? (m.source == "API" ? "VIA API" : "LOCAL ESTIMATE") : "\(m.plan) · \(m.source == "API" ? "VIA API" : "LOCAL")")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).tracking(0.6)
                }
                Spacer()
                Text(m.badge).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.3), lineWidth: 1))
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
                Button(action: onGear) { Image(systemName: "gearshape.fill") }.buttonStyle(.plain)
            }
            Divider()
            ForEach(m.rows) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.label).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(r.percent.map { "\(Int($0.rounded()))%" } ?? compact(r.tokens ?? 0)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    if let p = r.percent { UsageBar(fraction: p / 100) }
                    HStack {
                        Text(r.resets.map(resetsText) ?? r.caption ?? "no active window").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        if r.percent != nil, let t = r.tokens { Text("\(compact(t)) tokens").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                }
            }
            if !m.byModel.isEmpty {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("MODEL USAGE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.5)
                    Spacer()
                    Text(m.first.map { "since \(dfd.string(from: $0))" } ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                // One bar for the whole history: each model's slice is its share of all tokens.
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(m.byModel.enumerated()), id: \.offset) { _, e in
                            let share = m.all.total > 0 ? Double(e.1.total) / Double(m.all.total) : 0
                            RoundedRectangle(cornerRadius: 3).fill(modelColor(e.0))
                                .frame(width: max(share > 0 ? 4 : 0, share * (g.size.width - 2 * CGFloat(max(0, m.byModel.count - 1)))))
                        }
                    }
                }.frame(height: 10)
                VStack(spacing: 7) {
                    ForEach(Array(m.byModel.enumerated()), id: \.offset) { _, e in
                        let share = m.all.total > 0 ? Double(e.1.total) / Double(m.all.total) * 100 : 0
                        HStack(spacing: 8) {
                            Circle().fill(modelColor(e.0)).frame(width: 8, height: 8)
                            Text(prettyModel(e.0)).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(share < 1 && share > 0 ? "<1%" : "\(Int(share.rounded()))%").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                            Text(compact(e.1.total)).font(.system(size: 13, weight: .semibold).monospacedDigit()).frame(width: 64, alignment: .trailing)
                        }
                        .help("\(prettyModel(e.0)): \(e.1.msgs) messages · in \(compact(e.1.inp)) · out \(compact(e.1.out)) · cache write \(compact(e.1.cw)) · cache read \(compact(e.1.cr))")
                    }
                }
                HStack {
                    Text("\(m.all.msgs) messages").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(compact(m.all.total)) tokens in total").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("updated \(df.string(from: m.updated)) · source: \(m.source)").font(.system(size: 10)).foregroundStyle(.secondary)
                if let w = m.warning { Text(w).font(.system(size: 10)).foregroundStyle(.orange) }
                if let n = m.note { Text(n).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        .padding(18).frame(width: 370)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.18), lineWidth: 1))
    }
}

final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let scanner = TranscriptScanner()
    let model = UsageModel()
    let ud = UserDefaults.standard
    var panel: KeyPanel?
    var hosting: NSHostingView<PanelView>?
    var clickMonitor: Any?
    var timer: Timer?
    var lastApi: (at: Date, result: ApiResult)?
    var logo: NSImage?

    var limit5: Int? { let v = ud.integer(forKey: "limit5h"); return v > 0 ? v : nil }
    var limitW: Int? { let v = ud.integer(forKey: "limitWeek"); return v > 0 ? v : nil }
    var useApi: Bool { ud.bool(forKey: "useApi") }

    func applicationDidFinishLaunching(_ n: Notification) {
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"), let img = NSImage(contentsOf: url) {
            logo = img
            let t = img.copy() as! NSImage; t.size = NSSize(width: 17, height: 17); t.isTemplate = true
            item.button?.image = t
        }
        if logo == nil, let sym = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude usage") { sym.isTemplate = true; item.button?.image = sym }
        item.button?.imagePosition = .imageOnly          // icon only: no text in the menu bar
        item.button?.target = self; item.button?.action = #selector(toggle)
        let h = NSHostingView(rootView: PanelView(m: model, logo: logo, onRefresh: { [weak self] in self?.refresh(force: true) }, onGear: { [weak self] in self?.gearMenu() }))
        hosting = h
        refresh(force: false)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest") {   // diagnostics: render the panel to a PNG, print rows, exit
            let path = i + 1 < args.count ? args[i + 1] : "/tmp/claude-usage.png"
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [self] in
                for r in model.rows { print(r.label, r.percent.map { "\($0)%" } ?? "-", r.tokens.map { "tokens=\($0)" } ?? "", r.resets.map(resetsText) ?? "") }
                if args.contains("--demo") {   // preview only: pretend the exact limits came back
                    model.rows = [UsageRow(label: "Session (5h)", percent: 27, tokens: 2_332_106, resets: Date().addingTimeInterval(1200)),
                                  UsageRow(label: "Weekly (all models)", percent: 20, tokens: nil, resets: Date().addingTimeInterval(3 * 86400 + 13 * 3600)),
                                  UsageRow(label: "Weekly (Sonnet)", percent: 20, tokens: nil, resets: Date().addingTimeInterval(3 * 86400 + 13 * 3600))]
                    model.plan = "MAX"; model.source = "API"; model.note = nil; model.warning = nil
                    let opus = Totals(msgs: 412, inp: 1_200, out: 520_000, cw: 4_100_000, cr: 188_000_000)
                    let sonnet = Totals(msgs: 801, inp: 2_100, out: 790_000, cw: 9_300_000, cr: 340_000_000)
                    let haiku = Totals(msgs: 96, inp: 300, out: 61_000, cw: 410_000, cr: 5_000_000)
                    var all = Totals(); all.msgs = 1309; all.inp = 3_600; all.out = 1_371_000; all.cw = 13_810_000; all.cr = 533_000_000
                    model.byModel = [("claude-sonnet-5-5", sonnet), ("claude-opus-5-5", opus), ("claude-haiku-5-5", haiku)]
                    model.all = all; model.first = Date().addingTimeInterval(-20 * 86400)
                }
                print("models:", model.byModel.count, "total:", model.all.total)
                print("source:", model.source, "| note:", model.note ?? "-", "| warning:", model.warning ?? "-")
                let dark = args.contains("--dark")
                let card = PanelView(m: model, logo: logo, onRefresh: {}, onGear: {}).padding(28)
                    .background(dark ? Color(white: 0.07) : Color(white: 0.9)).environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: card); renderer.scale = 2
                if let ns = renderer.nsImage, let tiff = ns.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path)); print("wrote", path)
                }
                exit(0)
            }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh(force: false) }
    }

    func localRows(_ snap: Snapshot) -> [UsageRow] {
        [UsageRow(label: "Session (5h)", percent: limit5.flatMap { l in snap.block.map { Double($0.used) / Double(l) * 100 } } ?? (limit5 != nil ? 0 : nil),
                  tokens: snap.block?.used ?? 0, resets: snap.block?.end),
         UsageRow(label: "Weekly (7 days)", percent: limitW.map { Double(snap.week) / Double($0) * 100 }, tokens: snap.week, resets: nil, caption: "rolling last 7 days")]
    }

    func publish(_ snap: Snapshot, rows: [UsageRow], plan: String, source: String, note: String?, warning: String?) {
        model.rows = rows; model.plan = plan; model.source = source; model.note = note; model.warning = warning
        model.updated = Date(); model.byModel = snap.byModel; model.all = snap.all; model.first = snap.first
        let tip = rows.map { "\($0.label) \($0.percent.map { "\(Int($0.rounded()))%" } ?? compact($0.tokens ?? 0))" }.joined(separator: " · ")
        item.button?.toolTip = "Claude usage — " + tip
        resizePanel()
    }

    func refresh(force: Bool) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let snap = snapshot(scanner.scan())
            let hint = (!useApi && limit5 == nil && limitW == nil) ? "Token counts only. Use the gear to turn on exact limits from Claude, or set your own limits." : nil
            // 1) Local numbers go out straight away, so the panel never waits on the network.
            DispatchQueue.main.async {
                if self.useApi, !self.model.rows.isEmpty, self.model.source == "API" {
                    // keep the exact limits on screen; only the model usage is refreshed
                    self.model.byModel = snap.byModel; self.model.all = snap.all; self.model.first = snap.first; self.resizePanel()
                } else { self.publish(snap, rows: self.localRows(snap), plan: "", source: "local", note: hint, warning: nil) }
            }
            // 2) Exact limits (opt-in) fill in when Claude's servers answer.
            guard useApi else { return }
            let result: ApiResult
            if !force, let l = lastApi, Date().timeIntervalSince(l.at) < 120 { result = l.result }
            else { result = fetchApi(); lastApi = (Date(), result) }
            DispatchQueue.main.async {
                switch result {
                case .ok(let r, let p): self.publish(snap, rows: r, plan: p, source: "API", note: nil, warning: nil)
                case .fail(let why): self.publish(snap, rows: self.localRows(snap), plan: "", source: "local", note: nil, warning: why + ": showing local estimate instead")
                }
            }
        }
    }

    // MARK: panel
    @objc func toggle() { (panel?.isVisible ?? false) ? closePanel() : openPanel() }

    func openPanel() {
        guard let hosting, let btn = item.button, let bw = btn.window else { return }
        let p = panel ?? { let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .statusBar
            p.isMovable = false; p.contentView = hosting
            NotificationCenter.default.addObserver(self, selector: #selector(closePanel), name: NSWindow.didResignKeyNotification, object: p)
            panel = p; return p }()
        refresh(force: false)
        resizePanel()
        let r = bw.convertToScreen(btn.convert(btn.bounds, to: nil))
        let size = p.frame.size
        let vis = (bw.screen ?? NSScreen.main)!.visibleFrame
        let x = min(max(vis.minX + 8, r.midX - size.width / 2), vis.maxX - size.width - 8)
        p.setFrameOrigin(NSPoint(x: x, y: r.minY - size.height - 6))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.closePanel() }
    }
    @objc func closePanel() {
        panel?.orderOut(nil)
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }
    func resizePanel() {
        guard let hosting, let p = panel else { return }
        hosting.layoutSubtreeIfNeeded()
        let s = hosting.fittingSize
        if abs(p.frame.height - s.height) > 1 || abs(p.frame.width - s.width) > 1 {
            let top = p.frame.maxY
            p.setContentSize(s); p.setFrameOrigin(NSPoint(x: p.frame.minX, y: top - p.frame.height))
        }
    }

    // MARK: settings
    func gearMenu() {
        let m = NSMenu()
        func add(_ t: String, _ a: Selector, on: Bool = false) { let i = NSMenuItem(title: t, action: a, keyEquivalent: ""); i.target = self; i.state = on ? .on : .off; m.addItem(i) }
        add("Exact limits from Claude (uses your Claude login)", #selector(toggleApi), on: useApi)
        m.addItem(.separator())
        add("Set 5-hour limit… (local estimate)", #selector(set5)); add("Set weekly limit… (local estimate)", #selector(setW))
        m.addItem(.separator())
        add("Start at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        m.addItem(.separator())
        let q = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); m.addItem(q)
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    @objc func toggleApi() {
        if !useApi {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert(); a.messageText = "Use your Claude login for exact limits?"
            a.informativeText = "Claude Usage will read the sign-in token that Claude Code keeps in your Keychain and ask Claude's servers for your real 5-hour and weekly limits. macOS will ask you to allow this. Nothing is written or shared, and you can turn it off here at any time."
            a.addButton(withTitle: "Turn on"); a.addButton(withTitle: "Cancel")
            if a.runModal() != .alertFirstButtonReturn { return }
        }
        ud.set(!useApi, forKey: "useApi"); lastApi = nil; refresh(force: true)
    }
    @objc func set5() { askLimit("limit5h", "5-hour limit", "Tokens allowed per 5-hour window (e.g. 3m, 800k). Leave empty to clear.") }
    @objc func setW() { askLimit("limitWeek", "Weekly limit", "Tokens allowed per week (e.g. 40m). Leave empty to clear.") }
    func askLimit(_ key: String, _ title: String, _ msg: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = msg
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        let cur = ud.integer(forKey: key); f.stringValue = cur > 0 ? compact(cur) : ""
        a.accessoryView = f; a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            if f.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { ud.removeObject(forKey: key) }
            else if let v = parseCount(f.stringValue) { ud.set(v, forKey: key) }
            refresh(force: false)
        }
    }
    @objc func toggleLogin() {
        do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { NSSound.beep() }
    }
}

if CommandLine.arguments.contains("--dump") {   // diagnostics: print the local numbers and exit
    let s = snapshot(TranscriptScanner().scan())
    print("block:", s.block.map { "\($0.start) -> \($0.end) used=\($0.used)" } ?? "none", "| week:", s.week)
    for (m, t) in s.byModel { print(m, "msgs=\(t.msgs) in=\(t.inp) out=\(t.out) cw=\(t.cw) cr=\(t.cr)") }
    print("ALL msgs=\(s.all.msgs) total=\(s.all.total)")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App(); app.delegate = delegate
app.run()
