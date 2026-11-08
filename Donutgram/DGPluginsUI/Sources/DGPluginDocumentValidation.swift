import Foundation
import SwiftSignalKit
import DGPluginModel

final class DGPluginDocumentOperation<Output> {
    let disposable = MetaDisposable()
    private var completion: ((Result<Output, DGPluginError>?) -> Void)?

    init(completion: @escaping (Result<Output, DGPluginError>?) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<Output, DGPluginError>?) {
        guard let completion = self.completion else { return }
        self.completion = nil
        self.disposable.dispose()
        completion(result)
    }

    deinit { self.disposable.dispose() }
}

private let dgPluginDocumentDeadlineQueue = Queue(name: "donutgram.plugin.document-deadline", qos: .userInitiated)

func dgPluginValidateDocument<Input, Output>(source: Signal<Input, NoError>, timeout seconds: Double = 30, validate: @escaping (Input) throws -> Output) -> Signal<Result<Output, DGPluginError>, NoError> {
    let worker = Queue(name: "donutgram.plugin.document-validation", qos: .userInitiated)
    let result = source
    |> deliverOn(worker)
    |> map { value -> Result<Output, DGPluginError> in
        do { return .success(try validate(value)) }
        catch let error as DGPluginError { return .failure(error) }
        catch { return .failure(DGPluginError(code: "invalid_package", message: "unable to read or validate plugin document")) }
    }
    |> timeout(seconds, queue: dgPluginDocumentDeadlineQueue, alternate: .single(.failure(DGPluginError(code: "validation_timeout", message: "plugin document download or validation timed out; reopen the document to retry"))))
    |> take(1)
    return Signal { subscriber in
        let received = Atomic(value: false)
        return result.start(next: { value in
            let _ = received.swap(true)
            subscriber.putNext(value)
        }, completed: {
            if !received.with({ $0 }) {
                subscriber.putNext(.failure(DGPluginError(code: "download_failed", message: "plugin document completed without data; reopen the document to retry")))
            }
            subscriber.putCompletion()
        })
    }
}
