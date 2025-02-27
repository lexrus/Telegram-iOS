import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

public enum MusicPlaybackSettingsOrder: Int32 {
    case regular = 0
    case reversed = 1
    case random = 2
}

public enum MusicPlaybackSettingsLooping: Int32 {
    case none = 0
    case item = 1
    case all = 2
}

public enum AudioPlaybackRate: Int32 {
    case x0_5 = 500
    case x1 = 1000
    case x1_5 = 1500
    case x2 = 2000
    case x4 = 4000
    case x8 = 8000
    case x16 = 16000
    
    public var doubleValue: Double {
        return Double(self.rawValue) / 1000.0
    }

    public init(_ value: Double) {
        if let resolved = AudioPlaybackRate(rawValue: Int32(value * 1000.0)) {
            self = resolved
        } else {
            self = .x1
        }
    }
}

public struct MusicPlaybackSettings: PreferencesEntry, Equatable {
    public var order: MusicPlaybackSettingsOrder
    public var looping: MusicPlaybackSettingsLooping
    public var voicePlaybackRate: AudioPlaybackRate
    
    public static var defaultSettings: MusicPlaybackSettings {
        return MusicPlaybackSettings(order: .regular, looping: .none, voicePlaybackRate: .x1)
    }
    
    public init(order: MusicPlaybackSettingsOrder, looping: MusicPlaybackSettingsLooping, voicePlaybackRate: AudioPlaybackRate) {
        self.order = order
        self.looping = looping
        self.voicePlaybackRate = voicePlaybackRate
    }
    
    public init(decoder: PostboxDecoder) {
        self.order = MusicPlaybackSettingsOrder(rawValue: decoder.decodeInt32ForKey("order", orElse: 0)) ?? .regular
        self.looping = MusicPlaybackSettingsLooping(rawValue: decoder.decodeInt32ForKey("looping", orElse: 0)) ?? .none
        self.voicePlaybackRate = AudioPlaybackRate(rawValue: decoder.decodeInt32ForKey("voicePlaybackRate", orElse: AudioPlaybackRate.x1.rawValue)) ?? .x1
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.order.rawValue, forKey: "order")
        encoder.encodeInt32(self.looping.rawValue, forKey: "looping")
        encoder.encodeInt32(self.voicePlaybackRate.rawValue, forKey: "voicePlaybackRate")
    }
    
    public func isEqual(to: PreferencesEntry) -> Bool {
        if let to = to as? MusicPlaybackSettings {
            return self == to
        } else {
            return false
        }
    }
    
    public static func ==(lhs: MusicPlaybackSettings, rhs: MusicPlaybackSettings) -> Bool {
        return lhs.order == rhs.order && lhs.looping == rhs.looping && lhs.voicePlaybackRate == rhs.voicePlaybackRate
    }
    
    public func withUpdatedOrder(_ order: MusicPlaybackSettingsOrder) -> MusicPlaybackSettings {
        return MusicPlaybackSettings(order: order, looping: self.looping, voicePlaybackRate: self.voicePlaybackRate)
    }
    
    public func withUpdatedLooping(_ looping: MusicPlaybackSettingsLooping) -> MusicPlaybackSettings {
        return MusicPlaybackSettings(order: self.order, looping: looping, voicePlaybackRate: self.voicePlaybackRate)
    }
    
    public func withUpdatedVoicePlaybackRate(_ voicePlaybackRate: AudioPlaybackRate) -> MusicPlaybackSettings {
        return MusicPlaybackSettings(order: self.order, looping: self.looping, voicePlaybackRate: voicePlaybackRate)
    }
}

public func updateMusicPlaybackSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (MusicPlaybackSettings) -> MusicPlaybackSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.musicPlaybackSettings, { entry in
            let currentSettings: MusicPlaybackSettings
            if let entry = entry as? MusicPlaybackSettings {
                currentSettings = entry
            } else {
                currentSettings = MusicPlaybackSettings.defaultSettings
            }
            return f(currentSettings)
        })
    }
}
