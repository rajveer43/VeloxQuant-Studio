import Foundation
import Testing
@testable import VeloxQuantStudio

@MainActor
private final class FakeProfilingService: ProfilingServiceProtocol {
    var result: ProfileResponse?
    var errorToThrow: Error?
    /// Lets tests exercise the "still running" state before resolving.
    var continuation: CheckedContinuation<Void, Never>?
    var shouldSuspend = false

    func profile(request: ProfileRequest) async throws -> ProfileResponse {
        if shouldSuspend {
            await withCheckedContinuation { continuation = $0 }
        }
        if let errorToThrow { throw errorToThrow }
        guard let result else { throw ServiceError.decodingFailed }
        return result
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct HistoryViewModelTests {
    private func makeResponse() -> ProfileResponse {
        let json = """
        {
          "schema_version": 1,
          "model": "m", "method": "kivi", "bits": 4,
          "accounting_only": true, "accounting_note": "note",
          "layers": [{"layer_index": 0, "compute_latency_ms": 1.0, "is_fused": true, "peak_memory_bytes": 10, "compression_ratio": 1.0}],
          "summary": {"total_latency_ms": 1.0, "peak_memory_bytes": 10, "mean_compression_ratio": 1.0, "tokens_per_second": 1.0}
        }
        """
        return try! JSONDecoder().decode(ProfileResponse.self, from: Data(json.utf8))
    }

    private func makeJob(store: JobHistoryStore) -> QuantizationJob {
        store.createJob(modelName: "m", method: "kivi", bitWidth: 4, parametersJSON: "{}")
    }

    @Test func runProfileTransitionsIdleToLoadingToSuccess() async throws {
        let store = JobHistoryStore()
        let fake = FakeProfilingService()
        fake.result = makeResponse()
        let viewModel = HistoryViewModel(jobHistoryStore: store, profilingService: fake)
        let job = makeJob(store: store)

        #expect(viewModel.isProfiling(job) == false)
        #expect(viewModel.profileResult(for: job) == nil)

        viewModel.runProfile(for: job)
        #expect(viewModel.isProfiling(job) == true)

        // Allow the in-flight Task to run to completion.
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isProfiling(job) == false)
        #expect(viewModel.profileResult(for: job) != nil)
        #expect(viewModel.profileError(for: job) == nil)
    }

    @Test func runProfileTransitionsToFailureOnServiceError() async throws {
        let store = JobHistoryStore()
        let fake = FakeProfilingService()
        fake.errorToThrow = ServiceError.pythonNotConfigured
        let viewModel = HistoryViewModel(jobHistoryStore: store, profilingService: fake)
        let job = makeJob(store: store)

        viewModel.runProfile(for: job)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(viewModel.isProfiling(job) == false)
        #expect(viewModel.profileResult(for: job) == nil)
        #expect(viewModel.profileError(for: job) != nil)
    }

    @Test func runProfileIgnoresConcurrentCallsWhileInFlight() async throws {
        let store = JobHistoryStore()
        let fake = FakeProfilingService()
        fake.result = makeResponse()
        fake.shouldSuspend = true
        let viewModel = HistoryViewModel(jobHistoryStore: store, profilingService: fake)
        let job = makeJob(store: store)

        viewModel.runProfile(for: job)
        viewModel.runProfile(for: job) // should no-op while the first is in flight
        #expect(viewModel.isProfiling(job) == true)

        // Let the in-flight Task actually reach its suspension point before resuming it.
        try await Task.sleep(nanoseconds: 20_000_000)
        fake.resume()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(viewModel.isProfiling(job) == false)
    }

    @Test func cancelProfileClearsLoadingStateWithoutApplyingLateResult() async throws {
        let store = JobHistoryStore()
        let fake = FakeProfilingService()
        fake.result = makeResponse()
        fake.shouldSuspend = true
        let viewModel = HistoryViewModel(jobHistoryStore: store, profilingService: fake)
        let job = makeJob(store: store)

        viewModel.runProfile(for: job)
        #expect(viewModel.isProfiling(job) == true)

        viewModel.cancelProfile(for: job)
        #expect(viewModel.isProfiling(job) == false)

        fake.resume()
        try await Task.sleep(nanoseconds: 50_000_000)

        // The cancelled task must not have written a result after the fact.
        #expect(viewModel.profileResult(for: job) == nil)
    }
}
