import Foundation

@main struct Smoke {
    static func main() async {
        do {
            let receipt = try await IPPPrintClient().printBooklet(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: URL(string: CommandLine.arguments[2])!)
            print("ACCEPTED \(receipt.jobID ?? -1) \(receipt.format)")
        } catch {
            print("ERROR \(error.localizedDescription)")
            exit(1)
        }
    }
}
