import SwiftUI

struct FittingRoom: View {
    let items: [Item]
    @State private var artwork: [Int: URL] = [:]
    private var headless: Bool { items.contains(where: \.isHeadless) }
    private var wearables: [Item] {
        items.filter { $0.bundle != true && !$0.isHeadless && !(48...56).contains($0.slot ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fitting room").font(.title2.bold())
            Text("2D outfit preview").font(.footnote).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Color.indigo.opacity(0.11))
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 15).fill(Color.orange.opacity(0.45))
                        .frame(width: 55, height: 55).opacity(headless ? 0 : 1)
                    HStack(spacing: 4) {
                        part(24, 72)
                        part(65, 72)
                        part(24, 72)
                    }
                    HStack(spacing: 5) {
                        part(29, 65)
                        part(29, 65)
                    }
                }
                ForEach(Array(wearables.enumerated()), id: \.element.key) { index, item in
                    if let url = artwork[item.id] {
                        let onHead = [8, 41, 42].contains(item.slot ?? 0)
                        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { Color.clear }
                            .frame(width: 62, height: 62)
                            .offset(x: CGFloat((index % 3) - 1) * 24, y: onHead ? -84 : item.slot == 12 ? 65 : 4 + CGFloat(index % 3) * 19)
                            .accessibilityLabel(item.name)
                    }
                }
            }
            .frame(height: 240)
            .accessibilityLabel(headless ? "Headless outfit preview" : "Outfit preview")
        }
        .task(id: wearables.map(\.key)) {
            let ids = Array(Set(wearables.map(\.id))).sorted()
            var next: [Int: URL] = [:]
            for start in stride(from: 0, to: ids.count, by: 50) {
                let joined = ids[start..<min(start + 50, ids.count)].map(String.init).joined(separator: ",")
                let url = URL(string: "https://thumbnails.roblox.com/v1/assets?assetIds=\(joined)&size=150x150&format=Png&isCircular=false")!
                if let result = try? await PublicAvatar.request(URLRequest(url: url), as: Thumbnails.self) {
                    for row in result.data {
                        if let id = row.targetId, let url = row.imageUrl { next[id] = url }
                    }
                }
            }
            if !Task.isCancelled { artwork = next }
        }
    }

    private func part(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 9).fill(Color.indigo.opacity(0.28)).frame(width: width, height: height)
    }
}

struct CatalogShop: View {
    struct ResultRow: Decodable {
        let id: Int
        let name: String
        let itemType: String
        let assetType: Int?
        var item: Item { Item(id: id, name: name, bundle: itemType == "Bundle", kind: assetType) }
    }
    struct Results: Decodable { let data: [ResultRow] }

    let tryOn: (Item) -> Void
    @State private var query = ""
    @State private var items: [Item] = []
    @State private var loading = false
    @State private var status = ""

    var body: some View {
        NavigationStack {
            List {
                HStack {
                    TextField("Search Roblox catalog", text: $query)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }.disabled(loading)
                }
                if loading { ProgressView() }
                if !status.isEmpty { Text(status).foregroundStyle(.secondary) }
                ForEach(items, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name).font(.headline)
                        HStack {
                            Button("Try on") { tryOn(item) }.buttonStyle(.borderedProminent)
                            Link("View on Roblox", destination: item.url).buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 4)
                }
            }.navigationTitle("Shop")
            .task { if items.isEmpty { await search() } }
        }
    }

    private func search() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = URLComponents(string: "https://catalog.roblox.com/v1/search/items/details")!
        url.queryItems = [.init(name: "Category", value: "1"), .init(name: "Limit", value: "30")]
        if !keyword.isEmpty { url.queryItems?.append(.init(name: "Keyword", value: keyword)) }
        do {
            let results = try await PublicAvatar.request(URLRequest(url: url.url!), as: Results.self)
            var seen = Set<String>()
            items = results.data.map(\.item).filter { seen.insert($0.key).inserted }
            status = items.isEmpty ? "No matching items." : ""
        } catch {
            if !Task.isCancelled { status = "Couldn't load the catalog. Try again." }
        }
    }
}
