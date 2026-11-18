import SurgeCore
import SwiftUI

/// A provider dot never travels alone: the provider name always sits beside it.
public struct ProviderDot: View {
    private let provider: Provider
    private let size: CGFloat

    public init(provider: Provider) {
        self.init(provider: provider, size: SurgeUIStyle.providerDotSize)
    }

    public init(provider: Provider, size: CGFloat) {
        self.provider = provider
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(provider.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
