import Foundation
import Combine

// ViewModel that orchestrates: start session -> upload pages -> subscribe SSE -> update state.
// This is a minimal, self-contained VM for proof-of-readiness. Replace beginDemoSession() with real wiring.

final class ReaderNarrationViewModel: ObservableObject {
    @Published private(set) var jobID: String?
    @Published private(set) var progress: TNProgress?
    @Published private(set) var pages: [TNPageSnapshot] = []

    private var api: TNNarrationAPI
    private var sse: TNSSEClient = TNSSEClient()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // TODO: Parameterize via app config (UserDefaults/Info.plist)
let base = URL(string: UserDefaults.standard.string(forKey: "Tanoshi.APIBase") ?? "https://api.tanoshi.app")!
        self.api = TNNarrationAPI(baseURL: base)
    }

    func cancel() {
        sse.stop()
        jobID = nil
        progress = nil
        pages = []
    }

    // Demo kick-off to exercise the pipeline without real pages.
    // In production: assemble 20 PNG Data blobs for the current chapter window and call begin(chapterID:..., pages:..., voicePack:...)
    func beginDemoSession() {
        Task { await begin(chapterID: "demo:ch000", pages: [], voicePack: TNVoicePack(Narrator: "sovits:narrator-v1", MC: "sovits:mc-v1")) }
    }

    func begin(chapterID: String, pages: [Data], voicePack: TNVoicePack) async {
        do {
            let req = TNStartSessionRequest(
                chapter_id: chapterID,
                voice_pack: voicePack,
                window: TNWindow(start_index: 0, size: 20),
                client: TNClientInfo(device: "ios", app_version: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "")
            )
            let res = try await api.startSession(req)
            self.jobID = res.job_id
            self.progress = TNProgress(done: 0, total: 20)
            LogManager.logger.info("narration_start job=\(res.job_id)")

            // Upload PNGs if provided
            if !pages.isEmpty {
                let uploader = TNPageUploader()
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for plan in res.upload.pages {
                        if let data = pages.first(where: { _ in true }) { // TODO: map by index
                            group.addTask { try await uploader.upload(pageData: data, to: plan) }
                        }
                    }
                    try await group.waitForAll()
                }
            }

            // Subscribe SSE
            guard let url = URL(string: res.status_sse) else { return }
            sse.start(url: url, onEvent: { [weak self] event, data in
                self?.handle(event: event, data: data)
            }, onError: { err in
                LogManager.logger.error("sse_error: \(err)")
            })
        } catch {
            LogManager.logger.error("begin error: \(error)")
        }
    }

    private func handle(event: String, data: Data) {
        switch event {
        case "page_status":
            if let obj = try? JSONDecoder().decode(TNPageSnapshot.self, from: data) {
                upsert(page: obj)
            }
        case "page_ready":
            struct Ready: Codable { let index: Int; let audio: String; let duration: Double? }
            if let obj = try? JSONDecoder().decode(Ready.self, from: data) {
                upsert(page: TNPageSnapshot(index: obj.index, state: .ready, audio: obj.audio, reason: nil))
                if var prog = progress { prog.done += 1; progress = prog }
            }
        case "progress":
            if let prog = try? JSONDecoder().decode(TNProgress.self, from: data) {
                progress = prog
            }
        case "job_done":
            LogManager.logger.info("narration_done job=\(jobID ?? "?")")
        default:
            break
        }
    }

    private func upsert(page: TNPageSnapshot) {
        if let idx = pages.firstIndex(where: { $0.index == page.index }) {
            pages[idx] = page
        } else {
            pages.append(page)
        }
    }
}

