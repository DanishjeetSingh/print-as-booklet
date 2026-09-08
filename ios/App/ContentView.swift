import SwiftUI

private enum BookletStyle {
    static let ink = Color(red: 0.10, green: 0.23, blue: 0.18)
    static let paper = Color(uiColor: .systemGroupedBackground)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var documentURL: URL?
    @State private var articleLink = ""
    @StateObject private var printerNetwork = PrinterNetworkStatus()
    @StateObject private var signInSession = SubstackSignInSession()
    @State private var isFinishingSignIn = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 10) {
                        Image("BookletMark").resizable().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 9))
                        Text("PRINT AS BOOKLET").font(.caption.weight(.semibold)).tracking(2)
                        Spacer()
                    }
                    .padding(.top, 12)

                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Good reads.\nOn paper.")
                                .font(.system(size: 40, weight: .regular, design: .serif)).tracking(-1.5)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Turn an article into a small,\nbeautifully folded booklet.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image("BookletMark").resizable().scaledToFit()
                            .frame(width: 112).clipShape(RoundedRectangle(cornerRadius: 26))
                            .rotationEffect(.degrees(8)).shadow(color: .black.opacity(0.10), radius: 12, y: 8)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        Label("Make a booklet", systemImage: "doc.text").font(.headline)
                        TextField("Paste an article link", text: $articleLink)
                            .font(.subheadline).keyboardType(.URL).textContentType(.URL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).background(BookletStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Article URL")
                            .disabled(isPreparing)
                        status
                        actionButton
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                            Text("Letter paper"); Text("·"); Text("Two-sided"); Text("·"); Text("Fold & staple")
                        }.font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }.card()

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Quick Print setup", systemImage: "printer").font(.headline)
                        Text(printerNetwork.message).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button(printerNetwork.searching ? "Searching…" : "Find my printer") { printerNetwork.discover() }
                                .buttonStyle(.bordered).disabled(printerNetwork.searching)
                            if printerNetwork.searching { ProgressView() }
                            if printerNetwork.denied {
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                }.font(.subheadline)
                            }
                        }
                    }.card()

                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Even easier from Substack").font(.headline)
                            Spacer()
                            Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                        }
                        instruction("1", "Open an article", "Choose something you want to keep.")
                        instruction("2", "Share → Print as Booklet", "Prepare and print from the share panel.")
                        instruction("3", "Fold, staple, read", "Page order and binding marks are included.")
                    }.card()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Substack account").font(.subheadline.weight(.semibold))
                                Text(authenticationLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Sign in") { model.showingSignIn = true }.font(.subheadline.weight(.semibold))
                        }
                        if case let .failed(message) = model.authenticationState {
                            Text(message).font(.caption).foregroundStyle(.red)
                        }
                        Text("For subscriber-only articles, sign in where you print. The share panel will ask for its own sign-in once.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                    Text("A little less screen. A little more paper.")
                        .font(.system(.footnote, design: .serif)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.bottom, 8)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(colorScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Color(red: 0.96, green: 0.95, blue: 0.92))
            .tint(colorScheme == .dark ? Color(red: 0.55, green: 0.78, blue: 0.64) : BookletStyle.ink)
            .toolbar(.hidden, for: .navigationBar)
            .onDisappear { printerNetwork.stop() }
            .sheet(isPresented: $model.showingSignIn) {
                NavigationStack {
                    SubstackSignInView(session: signInSession)
                        .navigationTitle("Substack Sign In").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { model.showingSignIn = false }.disabled(isFinishingSignIn)
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    isFinishingSignIn = true
                                    Task {
                                        await signInSession.synchronizeCookies()
                                        await model.finishSignIn()
                                        isFinishingSignIn = false
                                    }
                                } label: {
                                    if isFinishingSignIn { ProgressView() } else { Text("Done") }
                                }.disabled(isFinishingSignIn)
                            }
                        }
                }.interactiveDismissDisabled(isFinishingSignIn)
            }
            .sheet(item: $documentURL) { url in
                AirPrintView(fileURL: url, onDismiss: { documentURL = nil })
            }
        }
    }

    private var isPreparing: Bool { model.state == .preparing }
    private var inputURL: URL? {
        guard let url = URL(string: articleLink.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }
    private var authenticationLabel: String {
        switch model.authenticationState {
        case .signedIn: "Signed in"
        case .verifying: "Checking sign-in…"
        default: "For subscriber-only articles"
        }
    }
    @ViewBuilder private var status: some View {
        switch model.state {
        case .preparing: ProgressView("Preparing your pages…").font(.subheadline)
        case let .prepared(_, count):
            Label("\(count) pages → \((count + 3) / 4) sheets", systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.secondary)
        case let .failed(message, _): Text(message).font(.subheadline).foregroundStyle(.red)
        default: EmptyView()
        }
    }
    @ViewBuilder private var actionButton: some View {
        if case let .prepared(url, _) = model.state {
            Button { documentURL = url } label: {
                Label("Print booklet", systemImage: "printer").frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent)
            Button("Start another booklet") { model.reset(); articleLink = "" }
                .font(.subheadline).frame(maxWidth: .infinity)
        } else {
            Button {
                guard let url = inputURL else { return }
                model.acceptArticleURL(url)
                Task { await model.prepare() }
            } label: {
                Label(isPreparing ? "Preparing…" : "Prepare booklet", systemImage: "book.closed")
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).disabled(inputURL == nil || isPreparing)
        }
    }
    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.weight(.semibold)).frame(width: 26, height: 26)
                .background(BookletStyle.paper, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    func card() -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
