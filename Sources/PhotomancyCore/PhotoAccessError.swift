import Foundation

/// How every security-scoped bookmark in this app is made.
///
/// `.securityScopeAllowOnlyReadAccess` is not optional here. Without it the
/// system tries to create a read-*write* scoped bookmark, which needs write
/// permission the app does not have and never asks for — its entitlement is
/// `files.user-selected.read-only`. The kernel then denies `file-write-data` and
/// the call fails with Cocoa error 256, having read the file happily a moment
/// earlier.
///
/// Only one route exposed this. A file opened through Open With or dropped from
/// the Finder arrives with a read-write extension, so a read-write bookmark
/// succeeds; the open panel's Powerbox grant matches the entitlement and is
/// read-only, so it does not. Bookmarking is the only operation that ever
/// noticed the difference.
let bookmarkCreationOptions: URL.BookmarkCreationOptions = [
    .withSecurityScope,
    .securityScopeAllowOnlyReadAccess,
]

public enum PhotoAccessError: Error, LocalizedError, Sendable {

    /// The bookmark resolved, but there is nothing at the other end any more.
    /// Files move. This is a normal state with a relink flow, not a crash.
    case missing(name: String)

    /// The bookmark could not be resolved at all — corrupt, or created by a
    /// differently-signed build of the app.
    case unresolvable(name: String, underlying: (any Error)?)

    /// `startAccessingSecurityScopedResource()` returned false. The token was
    /// understood and refused.
    case accessDenied(name: String)

    case notAnImage(name: String)

    case decodeFailed(name: String)

    public var errorDescription: String? {
        switch self {
        case .missing(let name):
            "“\(name)” is no longer where it was."
        case .unresolvable(let name, _):
            "Photomancy has lost permission to read “\(name)”."
        case .accessDenied(let name):
            "Photomancy was refused access to “\(name)”."
        case .notAnImage(let name):
            "“\(name)” is not an image Photomancy can read."
        case .decodeFailed(let name):
            "“\(name)” could not be decoded."
        }
    }
}
