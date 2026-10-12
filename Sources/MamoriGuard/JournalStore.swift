import Foundation
import Darwin
import MamoriCore

protocol GuardJournalStoring: Sendable {
    func load() throws -> GuardJournal?
    func save(_ journal: GuardJournal) throws
    func remove() throws
}

struct FileJournalStore: GuardJournalStoring {
    private let directory = URL(fileURLWithPath: "/Library/Application Support/Mamori", isDirectory: true)
    private var file: URL { directory.appendingPathComponent("guard-session.json") }
    private func inspectDirectory(create: Bool) throws -> Bool {
        if create && mkdir(directory.path, 0o700) != 0 && errno != EEXIST { throw GuardFailure.message("The guard could not create its recovery directory.") }
        var info = stat()
        guard lstat(directory.path, &info) == 0 else {
            if errno == ENOENT { return false }
            throw GuardFailure.message("The recovery directory could not be inspected.")
        }
        guard info.st_uid == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
            throw GuardFailure.message("The recovery directory has unsafe ownership or permissions.")
        }
        return true
    }
    func load() throws -> GuardJournal? {
        guard try inspectDirectory(create: false) else { return nil }
        var info = stat()
        guard lstat(file.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw GuardFailure.message("The recovery journal cannot be inspected.")
        }
        guard info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size < 131_072 else {
            throw GuardFailure.message("The recovery journal is not a safe private regular file.")
        }
        return try JSONDecoder().decode(GuardJournal.self, from: Data(contentsOf: file))
    }
    func save(_ journal: GuardJournal) throws {
        guard try inspectDirectory(create: true) else { throw GuardFailure.message("The recovery directory is missing.") }
        try JSONEncoder().encode(journal).write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw GuardFailure.message("The recovery journal permissions could not be set.") }
        // Persist the journal and directory entry before a kernel-state mutation.
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw GuardFailure.message("The recovery journal could not be synchronized.") }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw GuardFailure.message("The recovery journal could not be synchronized.") }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw GuardFailure.message("The recovery directory could not be synchronized.") }
        defer { close(parent) }
        guard fsync(parent) == 0 else { throw GuardFailure.message("The recovery directory could not be synchronized.") }
    }
    func remove() throws {
        guard try inspectDirectory(create: false) else { return }
        if try load() != nil { try FileManager.default.removeItem(at: file) }
        if rmdir(directory.path) != 0 && errno != ENOENT {
            throw GuardFailure.message("The private recovery directory is not empty or could not be removed. Mamori will not delete unknown files.")
        }
    }
}

func currentBootIdentifier() throws -> String {
    var count = 0
    guard sysctlbyname("kern.bootsessionuuid", nil, &count, nil, 0) == 0, count > 1, count < 256 else { throw GuardFailure.message("The current boot session could not be identified.") }
    var data = [CChar](repeating: 0, count: count)
    guard sysctlbyname("kern.bootsessionuuid", &data, &count, nil, 0) == 0 else { throw GuardFailure.message("The current boot session could not be identified.") }
    return String(decoding: data.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
