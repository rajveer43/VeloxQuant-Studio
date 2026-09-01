import Foundation
import SwiftData
import Observation

/// Owns the SwiftData container for job history and exposes a small,
/// view-friendly API. Kept separate from `QuantizationService`/
/// `BenchmarkService` so both can record jobs without depending on each
/// other.
@MainActor
@Observable
final class JobHistoryStore {
    let container: ModelContainer
    private(set) var jobs: [QuantizationJob] = []

    init() {
        let schema = Schema([QuantizationJob.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container for job history: \(error)")
        }
        refresh()
    }

    @discardableResult
    func createJob(modelName: String, method: String, bitWidth: Int, parametersJSON: String) -> QuantizationJob {
        let job = QuantizationJob(
            modelName: modelName,
            method: method,
            bitWidth: bitWidth,
            parametersJSON: parametersJSON
        )
        container.mainContext.insert(job)
        try? container.mainContext.save()
        refresh()
        return job
    }

    func appendLog(_ job: QuantizationJob, line: String) {
        job.logOutput += (job.logOutput.isEmpty ? "" : "\n") + line
        try? container.mainContext.save()
    }

    func complete(_ job: QuantizationJob, status: JobStatus, error: String? = nil, benchmark: BenchmarkResult? = nil) {
        job.finishedAt = .now
        job.status = status
        job.errorMessage = error
        if let benchmark, let data = try? JSONEncoder().encode(benchmark) {
            job.benchmarkResultJSON = String(data: data, encoding: .utf8)
        }
        try? container.mainContext.save()
        refresh()
    }

    /// Attaches (or overwrites) a profiling result for an already-completed
    /// job — profiling re-runs against the job's stored model/method/bits
    /// on demand from the History screen, rather than blocking the original
    /// serve/benchmark run. Overwrites any prior profileResultJSON, matching
    /// benchmarkResultJSON's one-job-one-result-blob convention.
    func attachProfile(_ job: QuantizationJob, result: ProfileResponse) {
        if let data = try? JSONEncoder().encode(result) {
            job.profileResultJSON = String(data: data, encoding: .utf8)
        }
        try? container.mainContext.save()
        refresh()
    }

    func delete(_ job: QuantizationJob) {
        container.mainContext.delete(job)
        try? container.mainContext.save()
        refresh()
    }

    func refresh() {
        let descriptor = FetchDescriptor<QuantizationJob>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        jobs = (try? container.mainContext.fetch(descriptor)) ?? []
    }
}
