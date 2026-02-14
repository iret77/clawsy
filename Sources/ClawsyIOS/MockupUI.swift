import SwiftUI
import ClawsyShared

#if os(iOS)
// MARK: - Clawsy iOS Mockup UI
// Focus: Sensor Nodes (Camera, Location) and Interaction Hub

struct IOSHomeView: View {
    @StateObject private var network = NetworkManager()
    @State private var locationEnabled = true
    @State private var showingCamera = false
    
    var body: some View {
        NavigationView {
            List {
                // --- Connection Section ---
                Section(header: Text("AGENT_STATUS")) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(network.isConnected ? "CONNECTED" : "DISCONNECTED")
                                .font(.headline)
                                .foregroundColor(network.isConnected ? .green : .red)
                            Text(network.connectionStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !network.isConnected {
                            Button("CONNECT") {
                                network.connect()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                // --- Sensor Nodes Section ---
                Section(header: Text("SENSOR_NODES")) {
                    // Camera Node
                    NavigationLink(destination: IOSCameraNodeView()) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("CAMERA_NODE")
                                Text("READY_FOR_REMOTE_EYE")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Location Node
                    Toggle(isOn: $locationEnabled) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("LOCATION_NODE")
                                Text(locationEnabled ? "SHARING_CONTEXT" : "PRIVACY_MODE")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "location.fill")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // --- Quick Actions ---
                Section(header: Text("QUICK_ACTIONS")) {
                    Button(action: { /* Trigger Share UI */ }) {
                        Label("SEND_MEMORY", systemImage: "brain.head.profile")
                    }
                    
                    Button(action: { /* Open Settings */ }) {
                        Label("SETTINGS", systemImage: "gearshape")
                    }
                }
                
                // --- Recent Activity (Push Log) ---
                Section(header: Text("RECENT_INTERACTIONS")) {
                    InteractionRow(title: "Agent", message: "Christian, I see you are at the office. Should I pull the latest Clawsy logs?")
                    InteractionRow(title: "Agent", message: "Reminder: Meeting with Alex in 15 mins.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clawsy")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Circle()
                        .fill(network.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
}

struct IOSCameraNodeView: View {
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black)
                    .aspectRatio(3/4, contentMode: .fit)
                
                VStack {
                    Image(systemName: "eye.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("AGENT_IS_WATCHING")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top)
                }
            }
            .padding()
            
            Text("The agent can request snapshots or a live stream when this node is active.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
            
            Button(action: { /* Local snap */ }) {
                Label("TAKE_MANUAL_SNAP", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)
        }
        .navigationTitle("Camera Node")
    }
}

struct InteractionRow: View {
    let title: String
    let message: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            Text(message)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct IOSHomeView_Previews: PreviewProvider {
    static var previews: some View {
        IOSHomeView()
            .preferredColorScheme(.dark)
    }
}
#endif
