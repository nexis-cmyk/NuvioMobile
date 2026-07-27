import Combine
import Foundation
import SharedCore

/// Resolves the currently focused Home hero's trailer after the configured dwell time.
///
/// Home only has lightweight `MetaPreview` cards, so trailers must be fetched from the
/// full metadata endpoint first. Every callback is keyed to the focused hero to prevent a
/// slow add-on response from starting a trailer for a card the user already left.
@MainActor
final class HomeHeroTrailerViewModel: ObservableObject {
    @Published private(set) var trailerURL: String?
    @Published private(set) var heroID: String?

    private var delayedStart: Task<Void, Never>?
    private var requestID = UUID()

    deinit { delayedStart?.cancel() }

    func schedule(
        for preview: MetaPreview?,
        isEnabled: Bool,
        isFocused: Bool,
        delaySeconds: Int
    ) {
        delayedStart?.cancel()
        requestID = UUID()
        trailerURL = nil
        heroID = nil

        guard isEnabled, isFocused, let preview else { return }

        let requestID = requestID
        let targetID: String = preview.id
        let targetType: String = preview.type
        delayedStart = Task { @MainActor [weak self] in
            let delay = UInt64(max(1, delaySeconds)) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.requestID == requestID else { return }

            // `fetch` is independent of the Detail screen's observable request state, so
            // Home prefetching cannot cancel or overwrite a detail page the user opens.
            MetaDetailsRepository.shared.fetch(type: targetType, id: targetID) { [weak self] meta, _ in
                DispatchQueue.main.async {
                    guard let self,
                          self.requestID == requestID,
                          let meta,
                          let trailer = HeroTrailerSelectorKt.selectHeroTrailer(trailers: meta.trailers) else {
                        return
                    }

                    HeroTrailerResolver.shared.resolveYouTube(youtubeUrl: trailer.youtubePlaybackUrl()) { [weak self] source, _ in
                        DispatchQueue.main.async {
                            guard let self,
                                  self.requestID == requestID,
                                  let url = source?.progressiveUrl,
                                  !url.isEmpty else {
                                return
                            }
                            self.heroID = targetID
                            self.trailerURL = url
                        }
                    }
                }
            }
        }
    }

    func trailerFailed(for heroID: String) {
        guard self.heroID == heroID else { return }
        trailerURL = nil
    }
}
