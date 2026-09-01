import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    private let jobHistoryStore: JobHistoryStore
    private let profilingService: ProfilingServiceProtocol

    var selectedJob: QuantizationJob?
    var statusFilter: JobStatus?

    /// Keyed by job id rather than a single shared flag, since multiple job
    /// rows could in principle be profiled independently.
    private(set) var profilingJobIDs: Set<UUID> = []
    private(set) var profileErrors: [UUID: String] = [:]
    private var profileTasks: [UUID: Task<Void, Never>] = [:]

    var jobs: [QuantizationJob] {
        let all = jobHistoryStore.jobs
        guard let statusFilter else { return all }
        return all.filter { $0.status == statusFilter }
    }

    var jobsWithBenchmarks: [QuantizationJob] {
        jobHistoryStore.jobs.filter { $0.benchmarkResultJSON != nil }
    }

    init(jobHistoryStore: JobHistoryStore, profilingService: ProfilingServiceProtocol) {
        self.jobHistoryStore = jobHistoryStore
        self.profilingService = profilingService
    }

    func refresh() {
        jobHistoryStore.refresh()
    }

    func delete(_ job: QuantizationJob) {
        cancelProfile(for: job)
        jobHistoryStore.delete(job)
        if selectedJob?.id == job.id {
            selectedJob = nil
        }
    }

    func benchmarkResult(for job: QuantizationJob) -> BenchmarkResult? {
        guard let json = job.benchmarkResultJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BenchmarkResult.self, from: data)
    }

    func profileResult(for job: QuantizationJob) -> ProfileResponse? {
        guard let json = job.profileResultJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProfileResponse.self, from: data)
    }

    func isProfiling(_ job: QuantizationJob) -> Bool {
        profilingJobIDs.contains(job.id)
    }

    func profileError(for job: QuantizationJob) -> String? {
        profileErrors[job.id]
    }

    /// Triggers a fresh profiling run reusing the job's stored
    /// model/method/bits/parameters — profiling is an on-demand action from
    /// History, not something the original serve/benchmark job blocks on.
    /// Re-running overwrites the prior result, matching benchmarkResultJSON's
    /// one-job-one-result-blob convention.
    func runProfile(for job: QuantizationJob) {
        guard !profilingJobIDs.contains(job.id) else { return }
        profilingJobIDs.insert(job.id)
        profileErrors[job.id] = nil

        let jobID = job.id
        let overrides = Self.decodeOverrides(job.parametersJSON)
        let request = ProfileRequest(
            model: LocalModel(repoID: job.modelName, sizeBytes: 0, sizeLabel: "", isMLXCommunity: false),
            method: job.method,
            bitWidth: job.bitWidth,
            parameterOverrides: overrides
        )

        profileTasks[jobID] = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await profilingService.profile(request: request)
                if Task.isCancelled { return }
                jobHistoryStore.attachProfile(job, result: result)
            } catch {
                if Task.isCancelled { return }
                profileErrors[jobID] = error.localizedDescription
            }
            profilingJobIDs.remove(jobID)
            profileTasks[jobID] = nil
        }
    }

    /// Cancels an in-flight profiling run — used when the user navigates away
    /// from the job (`.onDisappear`) or deletes it, so no stale loading state
    /// is left behind. `ProcessRunner.run` has no mid-flight cancellation of
    /// the subprocess itself, but dropping the awaiting Task stops the result
    /// from ever being applied to a job the user is no longer looking at.
    func cancelProfile(for job: QuantizationJob) {
        profileTasks[job.id]?.cancel()
        profileTasks[job.id] = nil
        profilingJobIDs.remove(job.id)
    }

    private static func decodeOverrides(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let overrides = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return overrides
    }
}
