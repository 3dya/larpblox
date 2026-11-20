import SwiftUI

struct Item: Codable, Identifiable {
    struct AssetType: Codable { let id: Int }
    let id: Int
    let name: String
    var bundle: Bool?
    var kind: Int?
    var assetType: AssetType?
    var slot: Int? { kind ?? assetType?.id }
    var isHeadless: Bool { bundle == true ? id == 201 : id == 134082579 }
    var key: String { "\(bundle == true ? "bundle" : "asset")-\(id)" }
    var url: URL { URL(string: "https://www.roblox.com/\(bundle == true ? "bundles" : "catalog")/\(id)")! }
}

struct Look: Codable, Identifiable {
    var id = UUID()
    var name: String
    var avatar: URL?
    var items: [Item]
}

struct Account: Decodable { let id: Int; let name: String }
struct Accounts: Decodable { let data: [Account] }
struct Avatar: Decodable { let assets: [Item] }
struct Thumbnail: Decodable { let imageUrl: URL?; let targetId: Int? }
struct Thumbnails: Decodable { let data: [Thumbnail] }

enum PublicAvatar {
    static func request<T: Decodable>(_ endpoint: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: endpoint)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func copy(_ input: String) async throws -> Look {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = URLComponents(string: query)
        let path = parts?.path.split(separator: "/") ?? []
        let id: Int
        let name: String
        if let value = Int(query), value > 0 {
            id = value
            name = "Roblox user \(value)"
        } else if let host = parts?.host?.lowercased(), ["roblox.com", "www.roblox.com"].contains(host),
                  path.count >= 3, path[0] == "users", path[2] == "profile", let value = Int(path[1]), value > 0 {
            id = value
            name = "Roblox user \(value)"
        } else {
            guard query.range(of: "^[a-zA-Z0-9_]{1,20}$", options: .regularExpression) != nil else { throw URLError(.badURL) }
            var lookup = URLRequest(url: URL(string: "https://users.roblox.com/v1/usernames/users")!)
            lookup.httpMethod = "POST"
            lookup.setValue("application/json", forHTTPHeaderField: "Content-Type")
            lookup.httpBody = try JSONSerialization.data(withJSONObject: ["usernames": [query], "excludeBannedUsers": true])
            guard let account = try await request(lookup, as: Accounts.self).data.first else { throw URLError(.resourceUnavailable) }
            id = account.id
            name = account.name
        }

        async let image = request(URLRequest(url: URL(string: "https://thumbnails.roblox.com/v1/users/avatar?userIds=\(id)&size=420x420&format=Png&isCircular=false")!), as: Thumbnails.self)
        let avatar = try await request(URLRequest(url: URL(string: "https://avatar.roblox.com/v1/users/\(id)/avatar")!), as: Avatar.self)
        let thumbnail = try? await image
        return Look(name: name, avatar: thumbnail?.data.first?.imageUrl, items: avatar.assets)
    }
}

@main struct CloudBlox: App {
    @AppStorage("appearance") private var appearance = "System"
    var body: some Scene {
        WindowGroup {
            Studio().preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        }
    }
}

struct Studio: View {
    @AppStorage("savedLooks") private var savedData = Data()
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("referenceImage") private var showImage = true
    @State private var tab = "Studio"
    @State private var query = ""
    @State private var look = Look(name: "", items: [])
    @State private var importing = false
    @State private var notice = ""
    @State private var itemInput = ""
    @State private var confirmClear = false

    private let quick = [
        Item(id: 201, name: "Headless Horseman", bundle: true),
        Item(id: 1365767, name: "Valkyrie Helm", kind: 8),
        Item(id: 1029025, name: "Classic Fedora", kind: 8),
    ]
    private var saved: [Look] { (try? JSONDecoder().decode([Look].self, from: savedData)) ?? [] }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("CloudBlox").font(.largeTitle.bold())
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Copy Avatar").font(.title2.bold())
                            TextField("Roblox username or profile URL", text: $query)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            Button(importing ? "Loading avatar…" : "Copy Avatar") {
                                Task {
                                    importing = true
                                    defer { importing = false }
                                    do { look = try await PublicAvatar.copy(query); notice = "Avatar copied to Studio." }
                                    catch { notice = "Couldn't load this avatar. Check the username or profile URL and try again." }
                                }
                            }.buttonStyle(.borderedProminent).disabled(importing || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if !notice.isEmpty { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                        }
                        FittingRoom(items: look.items)
                        if showImage, let url = look.avatar {
                            VStack(alignment: .leading) {
                                Text("Original avatar").font(.headline)
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else if phase.error != nil {
                                        Label("Image unavailable", systemImage: "photo")
                                    } else { ProgressView() }
                                }.frame(maxWidth: .infinity).frame(height: 230)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Try").font(.title2.bold())
                            Text("Add items to your outfit draft.").foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], alignment: .leading, spacing: 10) {
                                ForEach(quick, id: \.key) { item in
                                    Button { toggle(item) } label: {
                                        Label(item.name, systemImage: look.items.contains(where: { $0.key == item.key }) ? "checkmark.circle.fill" : "plus.circle")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Outfit editor").font(.title2.bold())
                            HStack {
                                TextField("Catalog item ID", text: $itemInput).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                                Button("Add") {
                                    guard let id = Int(itemInput), id > 0 else { return }
                                    let item = Item(id: id, name: "Catalog item \(id)")
                                    if !look.items.contains(where: { $0.key == item.key }) { look.items.append(item) }
                                    itemInput = ""
                                }.buttonStyle(.bordered)
                            }
                            if look.items.isEmpty { Text("Copy an avatar or add an item to start.").foregroundStyle(.secondary) }
                            ForEach(look.items, id: \.key) { item in
                                HStack {
                                    Text(item.name).frame(maxWidth: .infinity, alignment: .leading)
                                    Link(destination: item.url) { Image(systemName: "arrow.up.right.square") }.accessibilityLabel("View \(item.name) on Roblox")
                                    Button { look.items.removeAll { $0.key == item.key } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove \(item.name)")
                                }
                                Divider()
                            }
                            TextField("Look name", text: $look.name).textFieldStyle(.roundedBorder)
                            Button("Save Look") {
                                var copy = look
                                if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copy.name = "Look \(saved.count + 1)" }
                                persist([copy] + saved.filter { $0.id != copy.id })
                                tab = "Looks"
                            }.buttonStyle(.borderedProminent).disabled(look.items.isEmpty)
                        }
                    }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
            }.tabItem { Label("Studio", systemImage: "square.and.pencil") }.tag("Studio")

            CatalogShop { item in
                if !look.items.contains(where: { $0.key == item.key }) { look.items.append(item) }
                tab = "Studio"
            }.tabItem { Label("Shop", systemImage: "bag") }.tag("Shop")

            NavigationStack {
                List {
                    if saved.isEmpty { Text("Your saved looks will appear here.").foregroundStyle(.secondary) }
                    ForEach(saved) { entry in
                        Button { look = entry; tab = "Studio" } label: {
                            VStack(alignment: .leading) {
                                Text(entry.name).font(.headline)
                                Text("\(entry.items.count) items").foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { offsets in var remaining = saved; remaining.remove(atOffsets: offsets); persist(remaining) }
                }.navigationTitle("Saved Looks")
            }.tabItem { Label("Looks", systemImage: "bookmark") }.tag("Looks")

            NavigationStack {
                Form {
                    Section("Display") {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) }
                        }
                        Toggle("Show original avatar image", isOn: $showImage)
                    }
                    Section("Storage") {
                        Button("Clear saved looks", role: .destructive) { confirmClear = true }.disabled(saved.isEmpty)
                    }
                    Section("About") { Text("CloudBlox Studio · 0.1.0") }
                }.navigationTitle("Settings")
                    .confirmationDialog("Clear all saved looks?", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("Clear saved looks", role: .destructive) { persist([]) }
                    }
            }.tabItem { Label("Settings", systemImage: "gearshape") }.tag("Settings")
        }
    }

    private func persist(_ looks: [Look]) {
        if let data = try? JSONEncoder().encode(looks) { savedData = data }
    }

    private func toggle(_ item: Item) {
        if look.items.contains(where: { $0.key == item.key }) { look.items.removeAll { $0.key == item.key } }
        else { look.items.append(item) }
    }
}
