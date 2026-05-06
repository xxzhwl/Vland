#!/usr/bin/env swift
//
//  probe_claude_vscode_quota.swift
//  Vland — M7 前置验证脚本
//
//  目的：在不改 Vland 主工程的前提下，验证
//       VS Code 中 anthropic.claude-code 插件是否会把 rate_limits 打到日志里。
//
//  用法：
//       swift Vland/scripts/probe_claude_vscode_quota.swift
//       swift Vland/scripts/probe_claude_vscode_quota.swift --days 14 --tail 1048576
//       swift Vland/scripts/probe_claude_vscode_quota.swift --report ./vscode-quota-report.md
//
//  输出：
//       1) 控制台打印命中摘要
//       2) 生成一份 markdown 报告（默认 ./claude-vscode-probe-report.md）
//          含：扫描路径 / 命中文件列表 / 最新一条 rate_limits JSON dump /
//              与 CLI 字段对齐情况 / 下一步建议
//
//  不联网、不改任何文件、不动 VS Code 配置。
//

import Foundation

// MARK: - CLI 参数

struct Options {
    var days: Int = 7
    var tailBytes: Int = 512 * 1024
    var reportPath: String = "./claude-vscode-probe-report.md"
    var verbose: Bool = false
}

func parseOptions() -> Options {
    var opt = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--days":   if let v = it.next(), let n = Int(v) { opt.days = n }
        case "--tail":   if let v = it.next(), let n = Int(v) { opt.tailBytes = n }
        case "--report": if let v = it.next() { opt.reportPath = v }
        case "-v", "--verbose": opt.verbose = true
        case "-h", "--help":
            print("""
            Usage: probe_claude_vscode_quota.swift [--days N] [--tail BYTES] [--report PATH] [-v]
              --days N       扫描最近 N 天的日志（默认 7）
              --tail BYTES   每个文件倒读的字节数（默认 524288 = 512KB）
              --report PATH  markdown 报告输出路径（默认 ./claude-vscode-probe-report.md）
              -v, --verbose  打印每个扫描文件
            """)
            exit(0)
        default: break
        }
    }
    return opt
}

let opt = parseOptions()

// MARK: - 日志根目录（先只做 macOS）

let home = NSHomeDirectory()
let logRoots: [URL] = [
    URL(fileURLWithPath: home + "/Library/Application Support/Code/logs"),
    URL(fileURLWithPath: home + "/Library/Application Support/Code - Insiders/logs"),
    URL(fileURLWithPath: home + "/Library/Application Support/Cursor/logs"),
].filter { FileManager.default.fileExists(atPath: $0.path) }

// MARK: - 日志枚举

struct LogHit {
    var url: URL
    var size: Int64
    var mtime: Date
}

func enumerateLogs(under root: URL, maxAgeDays: Int) -> [LogHit] {
    let fm = FileManager.default
    let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
    let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
    guard let en = fm.enumerator(at: root,
                                  includingPropertiesForKeys: keys,
                                  options: [.skipsHiddenFiles]) else { return [] }
    var out: [LogHit] = []
    for case let url as URL in en {
        guard url.pathExtension == "log" else { continue }
        // 只关心路径里含 anthropic.claude-code 的文件
        guard url.path.contains("anthropic.claude-code")
           || url.lastPathComponent.contains("anthropic.claude-code") else { continue }
        let vals = try? url.resourceValues(forKeys: Set(keys))
        let mtime = vals?.contentModificationDate ?? .distantPast
        guard mtime >= cutoff else { continue }
        let size = Int64(vals?.fileSize ?? 0)
        out.append(LogHit(url: url, size: size, mtime: mtime))
    }
    return out.sorted { $0.mtime > $1.mtime }
}

// MARK: - 倒读尾部

func tailBytes(_ url: URL, maxBytes: Int) -> String? {
    guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? fh.close() }
    let end: UInt64 = (try? fh.seekToEnd()) ?? 0
    let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
    try? fh.seek(toOffset: start)
    let data = (try? fh.readToEnd()) ?? Data()
    // 可能截断了 UTF-8，粗暴回退
    return String(data: data, encoding: .utf8)
        ?? String(decoding: data, as: UTF8.self)
}

// MARK: - rate_limits 抽取

// 宽松匹配：抓到 "rate_limits" : { ... } 最外层大括号块。
// 为了应对嵌套，用手动括号计数而不是纯正则。
func extractRateLimitsBlocks(from text: String) -> [String] {
    var results: [String] = []
    // 兼容不同命名：rate_limits / rate_limit / ratelimits
    let anchors = ["\"rate_limits\"", "\"rate_limit\"", "\"ratelimits\""]
    var cursor = text.startIndex
    while cursor < text.endIndex {
        // 找到任一锚点的下一次出现
        var hitRange: Range<String.Index>? = nil
        for a in anchors {
            if let r = text.range(of: a, range: cursor..<text.endIndex) {
                if hitRange == nil || r.lowerBound < hitRange!.lowerBound {
                    hitRange = r
                }
            }
        }
        guard let r = hitRange else { break }
        // 跳过冒号/空白
        var idx = r.upperBound
        while idx < text.endIndex, let s = text[idx].asciiValue,
              s == 0x20 || s == 0x09 || s == 0x3A /* : */ { idx = text.index(after: idx) }
        guard idx < text.endIndex else { break }
        let open = text[idx]
        if open == "{" {
            // 括号计数到匹配
            var depth = 0
            var j = idx
            var inStr = false
            var esc = false
            while j < text.endIndex {
                let c = text[j]
                if inStr {
                    if esc { esc = false }
                    else if c == "\\" { esc = true }
                    else if c == "\"" { inStr = false }
                } else {
                    if c == "\"" { inStr = true }
                    else if c == "{" { depth += 1 }
                    else if c == "}" {
                        depth -= 1
                        if depth == 0 {
                            let block = String(text[idx...j])
                            results.append(block)
                            cursor = text.index(after: j)
                            break
                        }
                    }
                }
                j = text.index(after: j)
            }
            if j >= text.endIndex { break }
        } else {
            // 值不是对象（可能是数组/字符串），跳过本次
            cursor = r.upperBound
        }
    }
    return results
}

// MARK: - JSON 字段摘要

struct FieldSummary {
    var keys: [String] = []
    var sampleValues: [String: String] = [:]  // key -> 截断后的字符串
    var looksLikeCLIAlign: Bool = false        // 是否命中 CLI 的惯用字段
}

let cliFamiliarKeys: Set<String> = [
    "five_hour", "seven_day", "opus_7d", "sonnet_7d",
    "remaining_minutes", "reset_at", "resets_at",
    "used", "limit", "used_percentage", "used_percent",
    "window", "kind"
]

func summarize(block: String) -> FieldSummary {
    var s = FieldSummary()
    guard let data = block.data(using: .utf8) else { return s }
    guard let obj = try? JSONSerialization.jsonObject(with: data) else { return s }
    func walk(_ any: Any, prefix: String) {
        if let dict = any as? [String: Any] {
            for (k, v) in dict {
                let path = prefix.isEmpty ? k : "\(prefix).\(k)"
                s.keys.append(path)
                if cliFamiliarKeys.contains(k) { s.looksLikeCLIAlign = true }
                if v is [String: Any] || v is [Any] {
                    walk(v, prefix: path)
                } else {
                    let str = "\(v)"
                    s.sampleValues[path] = String(str.prefix(80))
                }
            }
        } else if let arr = any as? [Any] {
            for (i, v) in arr.enumerated() where i < 3 {
                walk(v, prefix: "\(prefix)[\(i)]")
            }
        }
    }
    walk(obj, prefix: "")
    s.keys.sort()
    return s
}

// MARK: - 主流程

print("== Claude Code VS Code 插件额度探测 ==")
print("扫描范围：近 \(opt.days) 天，每文件倒读 \(opt.tailBytes / 1024) KB")
print()

if logRoots.isEmpty {
    print("[警告] 未找到 VS Code / Cursor / VS Code Insiders 日志目录，退出。")
    exit(2)
}

var allHits: [LogHit] = []
for root in logRoots {
    print("扫描根目录：\(root.path)")
    let hits = enumerateLogs(under: root, maxAgeDays: opt.days)
    if hits.isEmpty {
        print("  (未发现 anthropic.claude-code 日志)")
    } else {
        print("  发现 \(hits.count) 个日志文件")
        if opt.verbose {
            for h in hits { print("    - \(h.url.lastPathComponent)  \(h.size) bytes  \(h.mtime)") }
        }
    }
    allHits.append(contentsOf: hits)
}
print()

struct BlockHit {
    var file: URL
    var block: String
    var summary: FieldSummary
}

var blockHits: [BlockHit] = []
for h in allHits {
    guard let tail = tailBytes(h.url, maxBytes: opt.tailBytes) else { continue }
    let blocks = extractRateLimitsBlocks(from: tail)
    for b in blocks {
        let s = summarize(block: b)
        blockHits.append(BlockHit(file: h.url, block: b, summary: s))
    }
}

print("命中 rate_limits 块总数：\(blockHits.count)")
if let latest = blockHits.first {
    print("最新命中文件：\(latest.file.lastPathComponent)")
    print("最新块字段数：\(latest.summary.keys.count)")
    print("与 CLI 字段对齐：\(latest.summary.looksLikeCLIAlign ? "✅" : "❌")")
}
print()

// MARK: - 生成 markdown 报告

func formatDate(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: d)
}

var md = ""
md += "# Claude Code VS Code 插件额度探测报告\n\n"
md += "- 生成时间：\(formatDate(Date()))\n"
md += "- 扫描范围：近 \(opt.days) 天\n"
md += "- 每文件倒读：\(opt.tailBytes / 1024) KB\n\n"

md += "## 1. 扫描根目录\n\n"
for r in logRoots { md += "- `\(r.path)`\n" }
md += "\n"

md += "## 2. 日志文件清单\n\n"
if allHits.isEmpty {
    md += "> ⚠️ 未发现 `anthropic.claude-code` 日志。可能原因：\n"
    md += "> 1) 未安装该插件；2) VS Code 日志按会话写入、窗口已关闭；3) 插件名变更。\n\n"
} else {
    md += "| 修改时间 | 大小 (KB) | 路径 |\n|---|---|---|\n"
    for h in allHits.prefix(50) {
        let kb = Double(h.size) / 1024.0
        md += "| \(formatDate(h.mtime)) | \(String(format: "%.1f", kb)) | `\(h.url.path.replacingOccurrences(of: home, with: "~"))` |\n"
    }
    if allHits.count > 50 { md += "\n_仅显示前 50 条_\n" }
    md += "\n"
}

md += "## 3. rate_limits 命中情况\n\n"
md += "- 命中块总数：**\(blockHits.count)**\n"
if blockHits.isEmpty {
    md += "\n> ⚠️ 没有抓到任何 `rate_limits` 块。建议：\n"
    md += "> 1. 检查 VS Code → Settings → `Claude Code: Log Level` 是否为 `debug`\n"
    md += "> 2. 在 VS Code 里与插件正常对话一次，再重新跑本脚本\n"
    md += "> 3. 若调到 debug 仍抓不到 → 走 **M8 Plan B**（配套桥接扩展抓响应头）\n\n"
} else {
    let aligned = blockHits.filter { $0.summary.looksLikeCLIAlign }.count
    md += "- 与 CLI 字段对齐（命中常见 key 如 `five_hour` / `seven_day` / `reset_at` 等）：**\(aligned) / \(blockHits.count)**\n\n"

    md += "### 3.1 最新一条 rate_limits（原文 JSON）\n\n"
    md += "来自：`\(blockHits[0].file.lastPathComponent)`\n\n"
    md += "```json\n"
    // 美化一下
    if let data = blockHits[0].block.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: pretty, encoding: .utf8) {
        md += str + "\n"
    } else {
        md += blockHits[0].block + "\n"
    }
    md += "```\n\n"

    md += "### 3.2 字段路径清单（最新块）\n\n"
    md += "| 字段路径 | 示例值 | 是否 CLI 惯用 |\n|---|---|---|\n"
    for k in blockHits[0].summary.keys {
        let v = blockHits[0].summary.sampleValues[k] ?? ""
        let leaf = k.split(separator: ".").last.map(String.init) ?? k
        let hit = cliFamiliarKeys.contains(leaf) ? "✅" : ""
        md += "| `\(k)` | `\(v)` | \(hit) |\n"
    }
    md += "\n"

    if blockHits.count > 1 {
        md += "### 3.3 其他命中块的字段差异\n\n"
        let baseline = Set(blockHits[0].summary.keys)
        for (i, bh) in blockHits.enumerated().dropFirst().prefix(5) {
            let now = Set(bh.summary.keys)
            let add = now.subtracting(baseline).sorted()
            let rem = baseline.subtracting(now).sorted()
            md += "- 块 #\(i) @ `\(bh.file.lastPathComponent)`：新增字段 \(add.count)，缺失字段 \(rem.count)\n"
            if !add.isEmpty { md += "  - 新增：\(add.prefix(8).map { "`\($0)`" }.joined(separator: ", "))\n" }
            if !rem.isEmpty { md += "  - 缺失：\(rem.prefix(8).map { "`\($0)`" }.joined(separator: ", "))\n" }
        }
        md += "\n"
    }
}

md += "## 4. 下一步判定\n\n"
if blockHits.isEmpty {
    md += "**结论**：主方案（日志 tail）暂不具备数据源。\n\n"
    md += "- 先引导用户把插件日志级别调到 `debug`\n"
    md += "- 复测一次；若仍空 → **跳过 M7，直接做 M8 Plan B**（VS Code 桥接扩展）\n"
} else if blockHits.contains(where: { $0.summary.looksLikeCLIAlign }) {
    md += "**结论**：主方案（日志 tail）**可行** ✅\n\n"
    md += "- 字段与 CLI rate_limits 结构基本对齐\n"
    md += "- 直接进入 **M7**：把本脚本的 `extractRateLimitsBlocks` + `summarize` 逻辑 Swift 化，\n"
    md += "  接入 `QuotaProviding` 协议；尾部倒读 + FSEvents 复用 `CodexQuotaProvider` 已有代码\n"
} else {
    md += "**结论**：抓到 `rate_limits` 但字段与 CLI **不对齐** ⚠️\n\n"
    md += "- 需要在 `ClaudeVSCodeQuotaProvider` 内做字段映射层（插件 schema → 内部 `QuotaWindow`）\n"
    md += "- 若映射难以稳定（多版本差异），**改走 M8 Plan B**（桥接扩展抓响应头）\n"
}

// MARK: - 写文件

let reportURL = URL(fileURLWithPath: opt.reportPath, relativeTo:
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
do {
    try md.write(to: reportURL, atomically: true, encoding: .utf8)
    print("报告已写入：\(reportURL.path)")
} catch {
    print("[错误] 无法写入报告：\(error)")
    exit(1)
}
