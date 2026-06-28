import Foundation

func withRetry<T>(attempts: Int = 3, _ op: () async throws -> T) async throws -> T {
    let delays: [UInt64] = [1_000_000_000, 4_000_000_000, 16_000_000_000]
    var lastError: Error!
    for i in 0..<attempts {
        do { return try await op() }
        catch let e as ServiceError {
            if case .httpError(let code) = e, code == 401 || code == 403 { throw e }
            lastError = e
        } catch let e as URLError { lastError = e }
        catch { throw error }
        if i < attempts - 1 { try await Task.sleep(nanoseconds: delays[i]) }
    }
    throw lastError!
}
