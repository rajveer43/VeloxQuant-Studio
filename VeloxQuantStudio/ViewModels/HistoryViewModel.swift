import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    private let jobHistoryStore: JobHistoryStore

    var selectedJob: QuantizationJob?
    var statusFilter: JobStatus?

    var jobs: [QuantizationJob] {
        let all = jobHistoryStore.jobs
        guard let statusFilter else { return all }
        return all.filter { $0.status == statusFilter }
    }

    var jobsWithBenchmarks: [QuantizationJob] {
        jobHistoryStore.jobs.filter { $0.benchmarkResultJSON != nil }
    }

    init(jobHistoryStore: JobHistoryStore) {
        self.jobHistoryStore = jobHistoryStore
    }

    func refresh() {
        jobHistoryStore.refresh()
    }

    func delete(_ job: QuantizationJob) {
        jobHistoryStore.delete(job)
        if selectedJob?.id == job.id {
            selectedJob = nil
        }
    }

    func benchmarkResult(for job: QuantizationJob) -> BenchmarkResult? {
        guard let json = job.benchmarkResultJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BenchmarkResult.self, from: data)
    }
}
