import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: RecentItemsStore
    @State private var searchText = ""

    private var filteredItems: [RecentItem] {
        store.filteredItems(matching: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            itemList
        }
        .padding(14)
        .frame(width: 420, height: 500)
        .task {
            store.refresh()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("最近打开")
                    .font(.headline)
                Text("Finder 打开的文件夹")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refresh()
                store.refreshFinderFolders()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    private var searchField: some View {
        TextField("搜索名称或路径", text: $searchText)
            .textFieldStyle(.roundedBorder)
    }

    private var itemList: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "暂无最近记录" : "没有匹配结果")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "最近文件夹")

                        ForEach(filteredItems) { item in
                            RecentItemRow(item: item) {
                                store.open(item)
                            } openAppName: {
                                store.openAppChoice(for: item).displayName
                            } openWithSystemDefaultAction: {
                                store.openAndRemember(item, with: .systemDefault)
                            } openWithTerminalAction: {
                                store.openAndRemember(item, with: .terminal)
                            } chooseOpenAppAction: {
                                store.chooseOpenApp(for: item)
                            } openTerminalAction: {
                                store.openTerminal(item)
                            } copyPathAction: {
                                store.copyPath(item)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .padding(.horizontal, 4)
    }
}

private struct RecentItemRow: View {
    let item: RecentItem
    let openAction: () -> Void
    let openAppName: () -> String
    let openWithSystemDefaultAction: () -> Void
    let openWithTerminalAction: () -> Void
    let chooseOpenAppAction: () -> Void
    let openTerminalAction: () -> Void
    let copyPathAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.systemImageName)
                .foregroundStyle(item.type.tintColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 8)
                }

                Text(item.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.source.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Menu {
                Button("打开", action: openAction)
                Menu("选择打开方式：\(openAppName())") {
                    Button("Finder", action: openWithSystemDefaultAction)
                    Button("终端", action: openWithTerminalAction)
                    Divider()
                    Button("选择应用...", action: chooseOpenAppAction)
                }
                Button("打开终端", action: openTerminalAction)
                Button("复制路径", action: copyPathAction)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openAction)
        .padding(10)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension RecentItem.ItemType {
    var systemImageName: String {
        switch self {
        case .folder:
            return "folder.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .folder:
            return .blue
        }
    }
}
