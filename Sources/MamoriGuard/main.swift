import Foundation
import Security
import MamoriCore
import MamoriGuardSupport
import Darwin

// This executable is exclusively a packaged SMAppService daemon, never a setuid CLI.
guard geteuid() == 0 else {
    fputs("MamoriGuard must be started through the approved Mamori background service.\n", stderr)
    exit(1)
}
var ownCode: SecCode?
var information: CFDictionary?
var staticCode: SecStaticCode?
var ownRequirement: SecRequirement?
guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode,
      SecRequirementCreateWithString("anchor apple generic and identifier \"\(GuardIdentity.service)\"" as CFString, [], &ownRequirement) == errSecSuccess,
      SecCodeCheckValidity(ownCode, [], ownRequirement) == errSecSuccess,
      SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let team = (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
      team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
    fputs("A valid Apple signing identity is required for MamoriGuard.\n", stderr)
    exit(1)
}
let listener = NSXPCListener(machServiceName: GuardIdentity.service)
listener.setConnectionCodeSigningRequirement("anchor apple generic and identifier \"\(GuardIdentity.app)\" and certificate leaf[subject.OU] = \"\(team)\"")
let delegate = GuardListener()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
