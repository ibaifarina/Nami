import SwiftUI

enum AppFont {
    static let heroTitle = Font.system(size: 40, weight: .bold)
    static let screenTitle = Font.system(.title, design: .default).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .default).weight(.semibold)
    static let cardTitle = Font.system(.subheadline).weight(.medium)
    static let cardMeta = Font.system(.caption)
    static let body = Font.system(.body)
    static let button = Font.system(.body).weight(.semibold)
}
