import SwiftUI

/// Small status indicator shown in the toolbar when a remote controller is active.
public struct RemoteControlStatusView: View {
    private final class StatusState {
        var isConnected = false
        var controllerName: String?
    }

    private let state = StatusState()

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.isConnected ? "arrow.right.circle.fill" : "arrow.right.circle")
                .foregroundColor(state.isConnected ? .green : .orange)

            if let name = state.controllerName {
                Text(name)
                    .font(.caption)
                    .foregroundColor(state.isConnected ? .green : .orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(state.isConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.3),
                                lineWidth: 1)
                )
        )
    }

    /// Call this from the controller to update the status.
    public func setRemoteController(name: String?) {
        state.controllerName = name
        state.isConnected = name != nil
    }

    public func clearRemoteController() {
        state.controllerName = nil
        state.isConnected = false
    }

    // Public getters for testing
    public var isConnectedPublic: Bool { state.isConnected }
    public var controllerNamePublic: String? { state.controllerName }
}

// MARK: - Previews
#if DEBUG
struct RemoteControlStatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RemoteControlStatusView()
                .onAppear {
                    let view = RemoteControlStatusView()
                    view.setRemoteController(name: "iPad Air")
                }

            RemoteControlStatusView()
        }
        .padding()
        .background(Color.gray)
    }
}
#endif
