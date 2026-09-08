import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var documentURL: URL?
    @StateObject private var signInSession = SubstackSignInSession()
    @State private var isFinishingSignIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "book.pages")
                    .font(.system(size: 58))
                    .foregroundStyle(.tint)

                Text("Print as Booklet")
                    .font(.largeTitle.bold())

                status

                Button("Sign in to Substack") {
                    model.showingSignIn = true
                }
                .buttonStyle(.bordered)

                authenticationStatus

                actionButton
            }
            .padding(24)
            .navigationTitle("Booklet Printer")
            .sheet(isPresented: $model.showingSignIn) {
                NavigationStack {
                    SubstackSignInView(session: signInSession)
                        .navigationTitle("Substack Sign In")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    isFinishingSignIn = true
                                    Task {
                                        await signInSession.synchronizeCookies()
                                        await model.finishSignIn()
                                        isFinishingSignIn = false
                                    }
                                } label: {
                                    if isFinishingSignIn {
                                        ProgressView()
                                    } else {
                                        Text("Done")
                                    }
                                }
                                .disabled(isFinishingSignIn)
                            }
                        }
                }
            }
            .sheet(item: $documentURL) { url in
                AirPrintView(fileURL: url)
            }
        }
    }

    @ViewBuilder
    private var authenticationStatus: some View {
        switch model.authenticationState {
        case .unknown:
            EmptyView()
        case .verifying:
            ProgressView("Confirming Substack sign-in…")
        case .signedIn:
            Label("Signed in to Substack", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .idle:
            Text("Share an article from the Substack app and choose Print as Booklet. The share panel will ask you to sign in when needed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case let .ready(url):
            VStack(spacing: 8) {
                Text("Article received")
                    .font(.headline)
                Text(url.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        case .preparing:
            ProgressView("Preparing booklet…")
        case let .prepared(_, pageCount):
            Text("Booklet ready from \(pageCount) source pages.")
                .font(.headline)
        case let .failed(message, _):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch model.state {
        case .ready:
            Button("Prepare Booklet") {
                Task { await model.prepare() }
            }
            .buttonStyle(.borderedProminent)
        case let .prepared(url, _):
            Button("Print Booklet") {
                documentURL = url
            }
            .buttonStyle(.borderedProminent)
        case .failed:
            Button("Try Again") {
                Task { await model.retry() }
            }
                .buttonStyle(.borderedProminent)
        default:
            EmptyView()
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
