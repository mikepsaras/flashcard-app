import SwiftUI

/// Rounded SF type scale — gives the app its clean, friendly feel.
enum Typography {
    static let cardTerm       = Font.system(size: 40, weight: .semibold, design: .rounded)
    static let cardDefinition = Font.system(size: 26, weight: .regular,  design: .rounded)
    static let largeTitle     = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title          = Font.system(.title2,     design: .rounded, weight: .semibold)
    static let headline       = Font.system(.headline,   design: .rounded)
    static let body           = Font.system(.body,       design: .rounded)
    static let callout        = Font.system(.callout,    design: .rounded)
    static let caption        = Font.system(.caption,    design: .rounded)
}
