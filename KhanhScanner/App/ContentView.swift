import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64))
            Text("Khanh Scanner")
                .font(.largeTitle.bold())
            Text("Turn paper into clean PDFs while keeping signatures and stamps in color.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
