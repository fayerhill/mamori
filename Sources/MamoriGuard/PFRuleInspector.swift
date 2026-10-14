import Foundation
import MamoriCore

struct PFRuleSnapshot {
    let rootRules: String
    let anchorRules: [String: String]
}

/// Enumerate literal paths: macOS's wildcard rule printer can return incomplete
/// output with exit status zero and a DIOCGETRULES diagnostic on stderr.
struct PFRuleInspector {
    let commands: any GuardCommandRunning

    /// Query only existing anchors. A missing anchor can produce DIOCGETRULES
    /// instead of an empty ruleset, including before activation and after flush.
    /// Prove absence from successful parent listings; never suppress a read error.
    func readOwnedRules() throws -> String {
        var parent = ""
        var listings: [(path: String, children: [String])] = []
        var exists = true
        for component in GuardIdentity.anchor.split(separator: "/") {
            let children = try childAnchors(of: parent)
            listings.append((parent, children))
            let child = parent.isEmpty ? String(component) : parent + "/" + component
            guard children.contains(child) else { exists = false; break }
            parent = child
        }
        let rules = exists ? try commands.pfRead(["-a", GuardIdentity.anchor, "-s", "rules"]) : ""
        for listing in listings {
            guard try childAnchors(of: listing.path) == listing.children else { throw inspectionFailure() }
        }
        return rules
    }

    func read() throws -> PFRuleSnapshot {
        let root = try commands.pfRead(["-s", "rules"])
        var pending = [""], index = 0
        var rules: [String: String] = [:], children: [String: [String]] = [:]
        var visited = Set<String>()
        while index < pending.count {
            let path = pending[index]
            index += 1
            guard visited.insert(path).inserted else { throw inspectionFailure() }
            if !path.isEmpty { rules[path] = try commands.pfRead(["-a", path, "-s", "rules"]) }
            let names = try childAnchors(of: path)
            children[path] = names
            guard pending.count + names.count <= 65 else { throw inspectionFailure() }
            pending.append(contentsOf: names)
        }
        // Refuse a topology change during inspection instead of overlooking a new sibling.
        for path in pending {
            guard try childAnchors(of: path) == children[path] else { throw inspectionFailure() }
        }
        guard GuardPolicy.meaningfulLines(try commands.pfRead(["-s", "rules"])) == GuardPolicy.meaningfulLines(root) else {
            throw inspectionFailure()
        }
        return PFRuleSnapshot(rootRules: root, anchorRules: rules)
    }

    private func childAnchors(of parent: String) throws -> [String] {
        let args = parent.isEmpty ? ["-s", "Anchors"] : ["-a", parent, "-s", "Anchors"]
        let lines = try commands.pfRead(args).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard lines.count <= 64, Set(lines).count == lines.count else { throw inspectionFailure() }
        for path in lines {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count <= 8, components.allSatisfy({
                $0 != "." && $0 != ".." && $0.range(of: #"\A[A-Za-z0-9_.-]+\z"#, options: .regularExpression) != nil
            }), (parent.isEmpty ? components.count == 1 : path.hasPrefix(parent + "/") && components.count == parent.split(separator: "/").count + 1) else {
                throw inspectionFailure()
            }
        }
        return lines
    }

    private func inspectionFailure() -> GuardFailure {
        .message("The firewall anchor hierarchy could not be read consistently. Protection or restoration is not confirmed.")
    }
}
