import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPermissions

public final class ApplicationSpecificBoolNotice: NoticeEntry {
    public init() {
    }
    
    public init(decoder: PostboxDecoder) {
    }
    
    public func encode(_ encoder: PostboxEncoder) {
    }
    
    public func isEqual(to: NoticeEntry) -> Bool {
        if let _ = to as? ApplicationSpecificBoolNotice {
            return true
        } else {
            return false
        }
    }
}

public final class ApplicationSpecificVariantNotice: NoticeEntry {
    public let value: Bool
    
    public init(value: Bool) {
        self.value = value
    }
    
    public init(decoder: PostboxDecoder) {
        self.value = decoder.decodeInt32ForKey("v", orElse: 0) != 0
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.value ? 1 : 0, forKey: "v")
    }
    
    public func isEqual(to: NoticeEntry) -> Bool {
        if let to = to as? ApplicationSpecificVariantNotice {
            if self.value != to.value {
                return false
            }
            return true
        } else {
            return false
        }
    }
}

public final class ApplicationSpecificCounterNotice: NoticeEntry {
    public let value: Int32
    
    public init(value: Int32) {
        self.value = value
    }
    
    public init(decoder: PostboxDecoder) {
        self.value = decoder.decodeInt32ForKey("v", orElse: 0)
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.value, forKey: "v")
    }
    
    public func isEqual(to: NoticeEntry) -> Bool {
        if let to = to as? ApplicationSpecificCounterNotice {
            if self.value != to.value {
                return false
            }
            return true
        } else {
            return false
        }
    }
}

public final class ApplicationSpecificTimestampNotice: NoticeEntry {
    public let value: Int32
    
    public init(value: Int32) {
        self.value = value
    }
    
    public init(decoder: PostboxDecoder) {
        self.value = decoder.decodeInt32ForKey("v", orElse: 0)
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.value, forKey: "v")
    }
    
    public func isEqual(to: NoticeEntry) -> Bool {
        if let to = to as? ApplicationSpecificTimestampNotice {
            if self.value != to.value {
                return false
            }
            return true
        } else {
            return false
        }
    }
}

public final class ApplicationSpecificInt64ArrayNotice: NoticeEntry {
    public let values: [Int64]
    
    public init(values: [Int64]) {
        self.values = values
    }
    
    public init(decoder: PostboxDecoder) {
        self.values = decoder.decodeInt64ArrayForKey("v")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64Array(self.values, forKey: "v")
    }
    
    public func isEqual(to: NoticeEntry) -> Bool {
        if let to = to as? ApplicationSpecificInt64ArrayNotice {
            if self.values != to.values {
                return false
            }
            return true
        } else {
            return false
        }
    }
}

private func noticeNamespace(namespace: Int32) -> ValueBoxKey {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: namespace)
    return key
}

private func noticeKey(peerId: PeerId, key: Int32) -> ValueBoxKey {
    let v = ValueBoxKey(length: 8 + 4)
    v.setInt64(0, value: peerId.toInt64())
    v.setInt32(8, value: key)
    return v
}

private enum ApplicationSpecificGlobalNotice: Int32 {
    case secretChatInlineBotUsage = 0
    case secretChatLinkPreviews = 1
    case proxyAdsAcknowledgment = 2
    case chatMediaMediaRecordingTips = 3
    case profileCallTips = 4
    case setPublicChannelLink = 5
    case passcodeLockTips = 6
    case contactsPermissionWarning = 7
    case notificationsPermissionWarning = 8
    case volumeButtonToUnmuteTip = 9
    case archiveChatTips = 10
    case archiveIntroDismissed = 11
    case cellularDataPermissionWarning = 13
    case chatMessageSearchResultsTip = 14
    case chatMessageOptionsTip = 15
    case chatTextSelectionTip = 16
    case themeChangeTip = 17
    case callsTabTip = 18
    case chatFolderTips = 19
    case locationProximityAlertTip = 20
    case nextChatSuggestionTip = 21
    case dismissedTrendingStickerPacks = 22
    case chatSpecificThemesDarkPreviewTip = 23
    case chatForwardOptionsTip = 24
    
    var key: ValueBoxKey {
        let v = ValueBoxKey(length: 4)
        v.setInt32(0, value: self.rawValue)
        return v
    }
}

private extension PermissionKind {
    var noticeKey: NoticeEntryKey? {
        switch self {
        case .contacts:
            return ApplicationSpecificNoticeKeys.contactsPermissionWarning()
        case .notifications:
            return ApplicationSpecificNoticeKeys.notificationsPermissionWarning()
        case .cellularData:
            return ApplicationSpecificNoticeKeys.cellularDataPermissionWarning()
        default:
            return nil
        }
    }
}

private struct ApplicationSpecificNoticeKeys {
    private static let botPaymentLiabilityNamespace: Int32 = 1
    private static let globalNamespace: Int32 = 2
    private static let permissionsNamespace: Int32 = 3
    private static let peerReportNamespace: Int32 = 4
    private static let inlineBotLocationRequestNamespace: Int32 = 5
    private static let psaAcknowledgementNamespace: Int32 = 6
    private static let botGameNoticeNamespace: Int32 = 7
    
    static func inlineBotLocationRequestNotice(peerId: PeerId) -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: inlineBotLocationRequestNamespace), key: noticeKey(peerId: peerId, key: 0))
    }
    
    static func botPaymentLiabilityNotice(peerId: PeerId) -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: botPaymentLiabilityNamespace), key: noticeKey(peerId: peerId, key: 0))
    }
    
    static func botGameNotice(peerId: PeerId) -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: botGameNoticeNamespace), key: noticeKey(peerId: peerId, key: 0))
    }
    
    static func irrelevantPeerGeoNotice(peerId: PeerId) -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: peerReportNamespace), key: noticeKey(peerId: peerId, key: 0))
    }
    
    static func secretChatInlineBotUsage() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.secretChatInlineBotUsage.key)
    }
    
    static func secretChatLinkPreviews() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.secretChatLinkPreviews.key)
    }
    
    static func archiveIntroDismissed() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.archiveIntroDismissed.key)
    }
    
    static func chatMediaMediaRecordingTips() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatMediaMediaRecordingTips.key)
    }
    
    static func archiveChatTips() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.archiveChatTips.key)
    }
    
    static func chatFolderTips() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatFolderTips.key)
    }
    
    static func profileCallTips() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.profileCallTips.key)
    }
    
    static func proxyAdsAcknowledgment() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.proxyAdsAcknowledgment.key)
    }
    
    static func psaAdsAcknowledgment(peerId: PeerId) -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: psaAcknowledgementNamespace), key: noticeKey(peerId: peerId, key: 0))
    }
    
    static func setPublicChannelLink() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.setPublicChannelLink.key)
    }
    
    static func passcodeLockTips() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.passcodeLockTips.key)
    }
    
    static func contactsPermissionWarning() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: permissionsNamespace), key: ApplicationSpecificGlobalNotice.contactsPermissionWarning.key)
    }
    
    static func notificationsPermissionWarning() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: permissionsNamespace), key: ApplicationSpecificGlobalNotice.notificationsPermissionWarning.key)
    }
    
    static func cellularDataPermissionWarning() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: permissionsNamespace), key: ApplicationSpecificGlobalNotice.cellularDataPermissionWarning.key)
    }
    
    static func volumeButtonToUnmuteTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.volumeButtonToUnmuteTip.key)
    }
    
    static func callsTabTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.callsTabTip.key)
    }
    
    static func chatMessageSearchResultsTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatMessageSearchResultsTip.key)
    }
    
    static func chatMessageOptionsTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatMessageOptionsTip.key)
    }
    
    static func chatTextSelectionTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatTextSelectionTip.key)
    }
    
    static func themeChangeTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.themeChangeTip.key)
    }
    
    static func locationProximityAlertTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.locationProximityAlertTip.key)
    }

    static func nextChatSuggestionTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.nextChatSuggestionTip.key)
    }
    
    static func dismissedTrendingStickerPacks() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.dismissedTrendingStickerPacks.key)
    }
    
    static func chatSpecificThemesDarkPreviewTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatSpecificThemesDarkPreviewTip.key)
    }
    
    static func chatForwardOptionsTip() -> NoticeEntryKey {
        return NoticeEntryKey(namespace: noticeNamespace(namespace: globalNamespace), key: ApplicationSpecificGlobalNotice.chatForwardOptionsTip.key)
    }
}

public struct ApplicationSpecificNotice {
    public static func irrelevantPeerGeoReportKey(peerId: PeerId) -> NoticeEntryKey {
        return ApplicationSpecificNoticeKeys.irrelevantPeerGeoNotice(peerId: peerId)
    }
    
    public static func setIrrelevantPeerGeoReport(postbox: Postbox, peerId: PeerId) -> Signal<Void, NoError> {
        return postbox.transaction { transaction -> Void in
            transaction.setNoticeEntry(key: ApplicationSpecificNoticeKeys.irrelevantPeerGeoNotice(peerId: peerId), value: ApplicationSpecificBoolNotice())
        }
    }
    
    public static func getBotPaymentLiability(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.botPaymentLiabilityNotice(peerId: peerId)) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setBotPaymentLiability(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.botPaymentLiabilityNotice(peerId: peerId), ApplicationSpecificBoolNotice())
        }
    }
    
    public static func getBotGameNotice(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.botGameNotice(peerId: peerId)) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setBotGameNotice(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.botGameNotice(peerId: peerId), ApplicationSpecificBoolNotice())
        }
    }
    
    public static func getInlineBotLocationRequest(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Int32?, NoError> {
        return accountManager.transaction { transaction -> Int32? in
            if let notice = transaction.getNotice(ApplicationSpecificNoticeKeys.inlineBotLocationRequestNotice(peerId: peerId)) as? ApplicationSpecificTimestampNotice {
                return notice.value
            } else {
                return nil
            }
        }
    }
    
    public static func inlineBotLocationRequestStatus(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Bool, NoError> {
        return accountManager.noticeEntry(key: ApplicationSpecificNoticeKeys.inlineBotLocationRequestNotice(peerId: peerId))
        |> map { view -> Bool in
            guard let value = view.value as? ApplicationSpecificTimestampNotice else {
                return false
            }
            if value.value == 0 {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func updateInlineBotLocationRequestState(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId, timestamp: Int32) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let notice = transaction.getNotice(ApplicationSpecificNoticeKeys.inlineBotLocationRequestNotice(peerId: peerId)) as? ApplicationSpecificTimestampNotice, (notice.value == 0 || timestamp <= notice.value + 10 * 60) {
                return false
            }
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.inlineBotLocationRequestNotice(peerId: peerId), ApplicationSpecificTimestampNotice(value: timestamp))
            
            return true
        }
    }
    
    public static func setInlineBotLocationRequest(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId, value: Int32) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.inlineBotLocationRequestNotice(peerId: peerId), ApplicationSpecificTimestampNotice(value: value))
        }
    }
    
    public static func getSecretChatInlineBotUsage(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.secretChatInlineBotUsage()) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setSecretChatInlineBotUsage(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.secretChatInlineBotUsage(), ApplicationSpecificBoolNotice())
        }
    }
    
    public static func setSecretChatInlineBotUsage(transaction: AccountManagerModifier<TelegramAccountManagerTypes>) {
        transaction.setNotice(ApplicationSpecificNoticeKeys.secretChatInlineBotUsage(), ApplicationSpecificBoolNotice())
    }
    
    public static func getSecretChatLinkPreviews(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool?, NoError> {
        return accountManager.transaction { transaction -> Bool? in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.secretChatLinkPreviews()) as? ApplicationSpecificVariantNotice {
                return value.value
            } else {
                return nil
            }
        }
    }
    
    public static func getSecretChatLinkPreviews(_ entry: NoticeEntry) -> Bool? {
        if let value = entry as? ApplicationSpecificVariantNotice {
            return value.value
        } else {
            return nil
        }
    }
    
    public static func setSecretChatLinkPreviews(accountManager: AccountManager<TelegramAccountManagerTypes>, value: Bool) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.secretChatLinkPreviews(), ApplicationSpecificVariantNotice(value: value))
        }
    }
    
    public static func setSecretChatLinkPreviews(transaction: AccountManagerModifier<TelegramAccountManagerTypes>, value: Bool) {
        transaction.setNotice(ApplicationSpecificNoticeKeys.secretChatLinkPreviews(), ApplicationSpecificVariantNotice(value: value))
    }
    
    public static func secretChatLinkPreviewsKey() -> NoticeEntryKey {
        return ApplicationSpecificNoticeKeys.secretChatLinkPreviews()
    }
    
    public static func getChatMediaMediaRecordingTips(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMediaMediaRecordingTips()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementChatMediaMediaRecordingTips(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMediaMediaRecordingTips()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatMediaMediaRecordingTips(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }
    
    public static func getArchiveChatTips(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.archiveChatTips()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementArchiveChatTips(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int = 1) -> Signal<Int, NoError> {
        return accountManager.transaction { transaction -> Int in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.archiveChatTips()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            let previousValue = currentValue
            currentValue += Int32(count)
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.archiveChatTips(), ApplicationSpecificCounterNotice(value: currentValue))
            
            return Int(previousValue)
        }
    }
    
    public static func incrementChatFolderTips(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int = 1) -> Signal<Int, NoError> {
        return accountManager.transaction { transaction -> Int in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatFolderTips()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            let previousValue = currentValue
            currentValue += Int32(count)
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatFolderTips(), ApplicationSpecificCounterNotice(value: currentValue))
            
            return Int(previousValue)
        }
    }
    
    public static func setArchiveIntroDismissed(transaction: AccountManagerModifier<TelegramAccountManagerTypes>, value: Bool) {
        transaction.setNotice(ApplicationSpecificNoticeKeys.archiveIntroDismissed(), ApplicationSpecificVariantNotice(value: value))
    }
    
    public static func archiveIntroDismissedKey() -> NoticeEntryKey {
        return ApplicationSpecificNoticeKeys.archiveIntroDismissed()
    }
    
    public static func getProfileCallTips(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.profileCallTips()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementProfileCallTips(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.profileCallTips()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.profileCallTips(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }
    
    public static func getSetPublicChannelLink(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.profileCallTips()) as? ApplicationSpecificCounterNotice {
                return value.value < 1
            } else {
                return true
            }
        }
    }
    
    public static func markAsSeenSetPublicChannelLink(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.profileCallTips(), ApplicationSpecificCounterNotice(value: 1))
        }
    }
    
    public static func getProxyAdsAcknowledgment(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.proxyAdsAcknowledgment()) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setProxyAdsAcknowledgment(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.proxyAdsAcknowledgment(), ApplicationSpecificBoolNotice())
        }
    }
    
    public static func getPsaAcknowledgment(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.psaAdsAcknowledgment(peerId: peerId)) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setPsaAcknowledgment(accountManager: AccountManager<TelegramAccountManagerTypes>, peerId: PeerId) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.psaAdsAcknowledgment(peerId: peerId), ApplicationSpecificBoolNotice())
        }
    }
    
    public static func getPasscodeLockTips(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.passcodeLockTips()) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setPasscodeLockTips(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.passcodeLockTips(), ApplicationSpecificBoolNotice())
        }
    }
    
    public static func permissionWarningKey(permission: PermissionKind) -> NoticeEntryKey? {
        return permission.noticeKey
    }
    
    public static func setPermissionWarning(accountManager: AccountManager<TelegramAccountManagerTypes>, permission: PermissionKind, value: Int32) {
        guard let noticeKey = permission.noticeKey else {
            return
        }
        let _ =  accountManager.transaction { transaction -> Void in
            transaction.setNotice(noticeKey, ApplicationSpecificTimestampNotice(value: value))
            }.start()
    }
    
    public static func getTimestampValue(_ entry: NoticeEntry) -> Int32? {
        if let value = entry as? ApplicationSpecificTimestampNotice {
            return value.value
        } else {
            return nil
        }
    }
    
    public static func getVolumeButtonToUnmute(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.volumeButtonToUnmuteTip()) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func setVolumeButtonToUnmute(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let _ = accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.volumeButtonToUnmuteTip(), ApplicationSpecificBoolNotice())
        }.start()
    }
    
    public static func getCallsTabTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.callsTabTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementCallsTabTips(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int = 1) -> Signal<Int, NoError> {
        return accountManager.transaction { transaction -> Int in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.callsTabTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            let previousValue = currentValue
            currentValue += min(3, Int32(count))
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.callsTabTip(), ApplicationSpecificCounterNotice(value: currentValue))
            
            return Int(previousValue)
        }
    }
    
    public static func setCallsTabTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.callsTabTip(), ApplicationSpecificBoolNotice())
        }
    }
    
    
    public static func getChatMessageSearchResultsTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMessageSearchResultsTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementChatMessageSearchResultsTip(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMessageSearchResultsTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatMessageSearchResultsTip(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }
    
    public static func getChatMessageOptionsTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMessageOptionsTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementChatMessageOptionsTip(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMessageOptionsTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatMessageOptionsTip(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }
    
    public static func getChatTextSelectionTips(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatTextSelectionTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementChatTextSelectionTips(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatTextSelectionTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatTextSelectionTip(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }
    
    public static func getThemeChangeTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
        return accountManager.transaction { transaction -> Bool in
            if let _ = transaction.getNotice(ApplicationSpecificNoticeKeys.themeChangeTip()) as? ApplicationSpecificBoolNotice {
                return true
            } else {
                return false
            }
        }
    }
    
    public static func markThemeChangeTipAsSeen(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let _ = accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.themeChangeTip(), ApplicationSpecificBoolNotice())
        }.start()
    }
    
    public static func getLocationProximityAlertTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMessageOptionsTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementLocationProximityAlertTip(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatMessageOptionsTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatMessageOptionsTip(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }

    public static func getNextChatSuggestionTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.nextChatSuggestionTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }

    public static func incrementNextChatSuggestionTip(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int32 = 1) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.nextChatSuggestionTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            currentValue += count

            transaction.setNotice(ApplicationSpecificNoticeKeys.nextChatSuggestionTip(), ApplicationSpecificCounterNotice(value: currentValue))
        }
    }
    
    public static func dismissedTrendingStickerPacks(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<[Int64]?, NoError> {
        return accountManager.noticeEntry(key: ApplicationSpecificNoticeKeys.dismissedTrendingStickerPacks())
        |> map { view -> [Int64]? in
            if let value = view.value as? ApplicationSpecificInt64ArrayNotice {
                return value.values
            } else {
                return nil
            }
        }
    }
    
    public static func setDismissedTrendingStickerPacks(accountManager: AccountManager<TelegramAccountManagerTypes>, values: [Int64]) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.setNotice(ApplicationSpecificNoticeKeys.dismissedTrendingStickerPacks(), ApplicationSpecificInt64ArrayNotice(values: values))
        }
    }
    
    public static func getChatSpecificThemesDarkPreviewTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatSpecificThemesDarkPreviewTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementChatSpecificThemesDarkPreviewTip(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int = 1) -> Signal<Int, NoError> {
        return accountManager.transaction { transaction -> Int in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatSpecificThemesDarkPreviewTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            let previousValue = currentValue
            currentValue += Int32(count)
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatSpecificThemesDarkPreviewTip(), ApplicationSpecificCounterNotice(value: currentValue))
            
            return Int(previousValue)
        }
    }
    
    public static func getChatForwardOptionsTip(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Int32, NoError> {
        return accountManager.transaction { transaction -> Int32 in
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatForwardOptionsTip()) as? ApplicationSpecificCounterNotice {
                return value.value
            } else {
                return 0
            }
        }
    }
    
    public static func incrementChatForwardOptionsTip(accountManager: AccountManager<TelegramAccountManagerTypes>, count: Int = 1) -> Signal<Int, NoError> {
        return accountManager.transaction { transaction -> Int in
            var currentValue: Int32 = 0
            if let value = transaction.getNotice(ApplicationSpecificNoticeKeys.chatForwardOptionsTip()) as? ApplicationSpecificCounterNotice {
                currentValue = value.value
            }
            let previousValue = currentValue
            currentValue += Int32(count)
            
            transaction.setNotice(ApplicationSpecificNoticeKeys.chatForwardOptionsTip(), ApplicationSpecificCounterNotice(value: currentValue))
            
            return Int(previousValue)
        }
    }
    
    public static func reset(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
        }
    }
}
