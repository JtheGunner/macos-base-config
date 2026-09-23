// Enable and select a keyboard layout as an input source, so it shows up in
// the input menu without a trip to System Settings.
//
//   swift enable-input-source.swift <path to .keylayout> <layout name>
//
// Registers the layout file first (a layout copied in this session is not
// known yet), then enables and selects the input source with that name.
// Exit 1 when the layout can't be found or enabled - System Settings and a
// log out / in are the fallback.
import Carbon
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("enable-input-source: \(message)\n".utf8))
    exit(1)
}

func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: enable-input-source.swift <keylayout> <name>\n".utf8))
    exit(2)
}
let layoutURL = URL(fileURLWithPath: arguments[1])
let layoutName = arguments[2]

// an already registered layout reports an error here; the lookup below decides
_ = TISRegisterInputSource(layoutURL as CFURL)

guard let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource],
      let source = sources.first(where: { property($0, kTISPropertyLocalizedName) == layoutName })
else {
    fail("no input source named '\(layoutName)' - log out and in, then run again")
}

let isEnabled: Bool = property(source, kTISPropertyInputSourceIsEnabled) ?? false
if isEnabled {
    print("  input source '\(layoutName)': already enabled")
} else {
    let status = TISEnableInputSource(source)
    guard status == noErr else { fail("enabling '\(layoutName)' failed (OSStatus \(status))") }
    print("  input source '\(layoutName)': enabled")
}

let status = TISSelectInputSource(source)
guard status == noErr else { fail("selecting '\(layoutName)' failed (OSStatus \(status))") }
print("  input source '\(layoutName)': selected")
