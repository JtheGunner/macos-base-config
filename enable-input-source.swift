// Enable and select a keyboard layout as an input source, so it shows up in
// the input menu without a trip to System Settings.
//
//   swift enable-input-source.swift <path to .keylayout> <layout name>
//   swift enable-input-source.swift --self-test
//
// Registers the layout file only when no input source with that name exists
// yet (a layout copied in this session is not known yet): registering a known
// layout again adds a second, disabled source under a new layout ID. Then it
// enables and selects the source with that name and names the layout that was
// selected before, so a switch to another layout in the meantime shows up.
// Exit 1 when the layout can't be found or enabled - System Settings and a
// log out / in are the fallback.
import Carbon
import Foundation

struct SourceState {
    let isEnabled: Bool
    let isSelected: Bool
}

// preferredSourceIndex -> the source to use when several share a name: the
// selected one, else the first enabled one, else the first one
func preferredSourceIndex(_ states: [SourceState]) -> Int? {
    if let selected = states.firstIndex(where: { $0.isSelected }) { return selected }
    if let enabled = states.firstIndex(where: { $0.isEnabled }) { return enabled }
    return states.isEmpty ? nil : 0
}

// selectionMessage -> the status line after selecting layoutName
func selectionMessage(_ layoutName: String, previous: String?) -> String {
    guard let previous = previous, previous != layoutName else {
        return "  input source '\(layoutName)': selected"
    }
    return "  input source '\(layoutName)': selected (was '\(previous)')"
}

func selfTest() -> Never {
    var failures = 0
    func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        guard actual != expected else { return }
        FileHandle.standardError.write(Data("FAIL: \(label): expected \(expected), got \(actual)\n".utf8))
        failures += 1
    }
    let disabled = SourceState(isEnabled: false, isSelected: false)
    let enabled = SourceState(isEnabled: true, isSelected: false)
    let selected = SourceState(isEnabled: true, isSelected: true)
    check(preferredSourceIndex([]), nil, "no source")
    check(preferredSourceIndex([disabled]), 0, "a single disabled source")
    check(preferredSourceIndex([disabled, enabled]), 1, "a disabled duplicate ahead of the enabled source")
    check(preferredSourceIndex([enabled, disabled, selected]), 2, "the selected source wins")
    check(selectionMessage("Custom", previous: "Swiss German"),
          "  input source 'Custom': selected (was 'Swiss German')", "switch from another layout")
    check(selectionMessage("Custom", previous: "Custom"), "  input source 'Custom': selected", "already selected")
    check(selectionMessage("Custom", previous: nil), "  input source 'Custom': selected", "unknown previous layout")
    print(failures == 0 ? "self-test passed" : "self-test: \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("enable-input-source: \(message)\n".utf8))
    exit(1)
}

func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
}

func sources(named name: String) -> [TISInputSource] {
    let all = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    return all.filter { property($0, kTISPropertyLocalizedName) == name }
}

func state(of source: TISInputSource) -> SourceState {
    SourceState(isEnabled: property(source, kTISPropertyInputSourceIsEnabled) ?? false,
                isSelected: property(source, kTISPropertyInputSourceIsSelected) ?? false)
}

let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "--self-test" { selfTest() }
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: enable-input-source.swift <keylayout> <name>\n".utf8))
    exit(2)
}
let layoutURL = URL(fileURLWithPath: arguments[1])
let layoutName = arguments[2]

var candidates = sources(named: layoutName)
if candidates.isEmpty {
    _ = TISRegisterInputSource(layoutURL as CFURL)
    candidates = sources(named: layoutName)
}
guard let index = preferredSourceIndex(candidates.map(state(of:))) else {
    fail("no input source named '\(layoutName)' - log out and in, then run again")
}
let source = candidates[index]

if state(of: source).isEnabled {
    print("  input source '\(layoutName)': already enabled")
} else {
    let status = TISEnableInputSource(source)
    guard status == noErr else { fail("enabling '\(layoutName)' failed (OSStatus \(status))") }
    print("  input source '\(layoutName)': enabled")
}

let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
let previousName: String? = current.flatMap { property($0, kTISPropertyLocalizedName) }
let status = TISSelectInputSource(source)
guard status == noErr else { fail("selecting '\(layoutName)' failed (OSStatus \(status))") }
print(selectionMessage(layoutName, previous: previousName))
