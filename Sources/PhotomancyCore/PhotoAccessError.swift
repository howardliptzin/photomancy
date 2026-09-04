import Foundation

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
