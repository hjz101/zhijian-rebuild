import SwiftUI

struct EngineSelfTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [EngineSelfTestItem] = []
    @State private var running = true

    var body: some View {
        NavigationStack {
            List {
                if running {
                    HStack(spacing: 10) { ProgressView(); Text("运行引擎自检…").foregroundStyle(ZJ.textSecondary) }
                        .listRowBackground(Color.clear)
                }
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.ok ? ZJ.celadon : Color(hex: 0xD65745))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                            Text(item.detail).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ZJ.textSecondary).lineLimit(3)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ZJ.bgBase.ignoresSafeArea())
            .navigationTitle("引擎自检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                running = true
                items = await EngineSelfTest.run()
                running = false
            }
        }
    }
}
