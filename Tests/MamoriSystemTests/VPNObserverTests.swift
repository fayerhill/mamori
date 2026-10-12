import Testing
@testable import MamoriSystem

struct VPNObserverTests {
    @Test func recognizesTheInstalledGlobalProtectClientIdentifier() {
        #expect(VPNObserver.isGlobalProtectClient("com.paloaltonetworks.GlobalProtect.client"))
        #expect(VPNObserver.isGlobalProtectClient("COM.PALOALTONETWORKS.GLOBALPROTECT.CLIENT"))
    }

    @Test func retainsTheRecognizedBaseIdentifierWithoutCaseSensitivity() {
        #expect(VPNObserver.isGlobalProtectClient("com.paloaltonetworks.globalprotect"))
        #expect(VPNObserver.isGlobalProtectClient("com.PaloAltoNetworks.GlobalProtect"))
    }

    @Test func rejectsUnrecognizedPrefixesSuffixesAndHelperIdentifiers() {
        for identifier in [
            "com.paloaltonetworks.globalprotect.client.helper",
            "com.paloaltonetworks.globalprotect.clientfake",
            "com.paloaltonetworks.globalprotect.helper",
            "example.com.paloaltonetworks.globalprotect",
            "com.paloaltonetworks.globalprotect2"
        ] {
            #expect(!VPNObserver.isGlobalProtectClient(identifier))
        }
    }

    @Test func rejectsMissingEmptyAndWhitespacePaddedIdentifiers() {
        #expect(!VPNObserver.isGlobalProtectClient(nil))
        #expect(!VPNObserver.isGlobalProtectClient(""))
        #expect(!VPNObserver.isGlobalProtectClient(" com.paloaltonetworks.globalprotect.client"))
        #expect(!VPNObserver.isGlobalProtectClient("com.paloaltonetworks.globalprotect.client\n"))
    }
}
