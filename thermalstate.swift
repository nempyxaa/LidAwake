// Prints the macOS thermal pressure level: 0 nominal, 1 fair, 2 serious, 3 critical.
// Universal signal on Intel and Apple Silicon (NSProcessInfo, macOS 10.10.3+).
import Foundation
print(ProcessInfo.processInfo.thermalState.rawValue)
