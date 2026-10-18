import Foundation

/// Why a link could not be turned into media. `reason` is the Russian text shown on the toast.
public enum DGLinkDownloadError: Error, Equatable {
    case cancelled
    case tiktokLinkExpired
    case tiktokNotFound
    case tiktokPrivate
    case tiktokStatus(Int)
    case tiktokNoData
    case tiktokPageStatus(Int)
    case tiktokPageDenied
    case tiktokBotCheck
    case tiktokFileStatus(Int)
    case tiktokUnavailable
    case tiktokDownloadServiceStatus(Int)
    /// TikTok refused (first) and TikWM failed after it (second): TikWM's answer alone hides why TikTok refused.
    indirect case tiktokFailed(DGLinkDownloadError, DGLinkDownloadError)
    case youtubeLoginRequired
    case youtubeAgeRestricted
    case youtubeUnavailable
    case youtubeTooLong
    case noCompatibleFormat
    case tooLarge
    case httpStatus(Int)
    case network(URLError.Code)
    case processingFailed

    init(_ error: Error) {
        if let urlError = error as? URLError {
            self = urlError.code == .cancelled ? .cancelled : .network(urlError.code)
        } else {
            self = .network(.unknown)
        }
    }

    public var reason: String {
        switch self {
        case .cancelled:
            return "Скачивание отменено"
        case .tiktokLinkExpired:
            return "Ссылка TikTok устарела или неверная"
        case .tiktokNotFound:
            return "Видео удалено или недоступно"
        case .tiktokPrivate:
            return "Закрытый аккаунт"
        case let .tiktokStatus(code):
            return "TikTok не отдал видео (код \(code))"
        case .tiktokNoData:
            return "TikTok прислал страницу без видео"
        case let .tiktokPageStatus(code):
            return "TikTok не отдал страницу (HTTP \(code))"
        case .tiktokPageDenied:
            return "TikTok отклонил запрос"
        case .tiktokBotCheck:
            return "TikTok не пропустил проверку на бота"
        case let .tiktokFileStatus(code):
            return "TikTok не отдал файл (HTTP \(code))"
        case .tiktokUnavailable:
            return "Сервис скачивания TikTok не отдал видео"
        case let .tiktokDownloadServiceStatus(code):
            return "Сервис скачивания TikTok вернул HTTP \(code)"
        case let .tiktokFailed(direct, fallback):
            return [direct.reason, fallback.reason].map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.joined(separator: ". ")
        case .youtubeLoginRequired:
            return "YouTube просит войти в аккаунт"
        case .youtubeAgeRestricted:
            return "Видео 18+, без входа не скачать"
        case .youtubeUnavailable:
            return "Видео недоступно"
        case .youtubeTooLong:
            return "Это не Shorts, а длинное видео"
        case .noCompatibleFormat:
            return "Нет подходящего формата"
        case .tooLarge:
            return "Файл больше 200 МБ"
        case let .httpStatus(code):
            return "Сервер не отдал файл (HTTP \(code))"
        case let .network(code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "Нет интернета"
            case .timedOut:
                return "Сервер долго не отвечает"
            default:
                return URLError(code).localizedDescription
            }
        case .processingFailed:
            return "Не удалось обработать файл"
        }
    }
}
