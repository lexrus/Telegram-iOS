import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit

func fetchAndUpdateSupplementalCachedPeerData(peerId rawPeerId: PeerId, network: Network, postbox: Postbox) -> Signal<Bool, NoError> {
    return postbox.combinedView(keys: [.basicPeer(rawPeerId)])
    |> mapToSignal { views -> Signal<Peer, NoError> in
        guard let view = views.views[.basicPeer(rawPeerId)] as? BasicPeerView else {
            return .complete()
        }
        guard let peer = view.peer else {
            return .complete()
        }
        return .single(peer)
    }
    |> take(1)
    |> mapToSignal { _ -> Signal<Bool, NoError> in
        return postbox.transaction { transaction -> Signal<Bool, NoError> in
            guard let rawPeer = transaction.getPeer(rawPeerId) else {
                return .single(false)
            }
            
            let peer: Peer
            if let secretChat = rawPeer as? TelegramSecretChat {
                guard let user = transaction.getPeer(secretChat.regularPeerId) else {
                    return .single(false)
                }
                peer = user
            } else {
                peer = rawPeer
            }
                
            let cachedData = transaction.getPeerCachedData(peerId: peer.id)
            
            if let cachedData = cachedData as? CachedUserData {
                if cachedData.peerStatusSettings != nil {
                    return .single(true)
                }
            } else if let cachedData = cachedData as? CachedGroupData {
                if cachedData.peerStatusSettings != nil {
                    return .single(true)
                }
            } else if let cachedData = cachedData as? CachedChannelData {
                if cachedData.peerStatusSettings != nil {
                    return .single(true)
                }
            } else if let cachedData = cachedData as? CachedSecretChatData {
                if cachedData.peerStatusSettings != nil {
                    return .single(true)
                }
            }
            
            if peer.id.namespace == Namespaces.Peer.SecretChat {
                return postbox.transaction { transaction -> Bool in
                    var peerStatusSettings: PeerStatusSettings
                    if let peer = transaction.getPeer(peer.id), let associatedPeerId = peer.associatedPeerId, !transaction.isPeerContact(peerId: associatedPeerId) {
                        if let peer = peer as? TelegramSecretChat, case .creator = peer.role {
                            peerStatusSettings = PeerStatusSettings(flags: [])
                        } else {
                            peerStatusSettings = PeerStatusSettings(flags: [.canReport])
                        }
                    } else {
                        peerStatusSettings = PeerStatusSettings(flags: [])
                    }
                    
                    transaction.updatePeerCachedData(peerIds: [peer.id], update: { peerId, current in
                        if let current = current as? CachedSecretChatData {
                            return current.withUpdatedPeerStatusSettings(peerStatusSettings)
                        } else {
                            return CachedSecretChatData(peerStatusSettings: peerStatusSettings)
                        }
                    })
                    
                    return true
                }
            } else if let inputPeer = apiInputPeer(peer) {
                return network.request(Api.functions.messages.getPeerSettings(peer: inputPeer))
                |> retryRequest
                |> mapToSignal { peerSettings -> Signal<Bool, NoError> in
                    let peerStatusSettings = PeerStatusSettings(apiSettings: peerSettings)
                    
                    return postbox.transaction { transaction -> Bool in
                        transaction.updatePeerCachedData(peerIds: Set([peer.id]), update: { _, current in
                            switch peer.id.namespace {
                                case Namespaces.Peer.CloudUser:
                                    let previous: CachedUserData
                                    if let current = current as? CachedUserData {
                                        previous = current
                                    } else {
                                        previous = CachedUserData()
                                    }
                                    return previous.withUpdatedPeerStatusSettings(peerStatusSettings)
                                case Namespaces.Peer.CloudGroup:
                                    let previous: CachedGroupData
                                    if let current = current as? CachedGroupData {
                                        previous = current
                                    } else {
                                        previous = CachedGroupData()
                                    }
                                    return previous.withUpdatedPeerStatusSettings(peerStatusSettings)
                                case Namespaces.Peer.CloudChannel:
                                    let previous: CachedChannelData
                                    if let current = current as? CachedChannelData {
                                        previous = current
                                    } else {
                                        previous = CachedChannelData()
                                    }
                                    return previous.withUpdatedPeerStatusSettings(peerStatusSettings)
                                default:
                                    break
                            }
                            return current
                        })
                        return true
                    }
                }
            } else {
                return .single(false)
            }
        }
        |> switchToLatest
    }
}

func _internal_fetchAndUpdateCachedPeerData(accountPeerId: PeerId, peerId rawPeerId: PeerId, network: Network, postbox: Postbox) -> Signal<Bool, NoError> {
    return postbox.combinedView(keys: [.basicPeer(rawPeerId)])
    |> mapToSignal { views -> Signal<Bool, NoError> in
        if accountPeerId == rawPeerId {
            return .single(true)
        }
        guard let view = views.views[.basicPeer(rawPeerId)] as? BasicPeerView else {
            return .complete()
        }
        guard let _ = view.peer else {
            return .complete()
        }
        return .single(true)
    }
    |> take(1)
    |> mapToSignal { _ -> Signal<Bool, NoError> in
        return postbox.transaction { transaction -> (Api.InputUser?, Peer?, PeerId) in
            guard let rawPeer = transaction.getPeer(rawPeerId) else {
                if rawPeerId == accountPeerId {
                    return (.inputUserSelf, transaction.getPeer(rawPeerId), rawPeerId)
                } else {
                    return (nil, nil, rawPeerId)
                }
            }
            
            let peer: Peer
            if let secretChat = rawPeer as? TelegramSecretChat {
                guard let user = transaction.getPeer(secretChat.regularPeerId) else {
                    return (nil, nil, rawPeerId)
                }
                peer = user
            } else {
                peer = rawPeer
            }
            
            if rawPeerId == accountPeerId {
                return (.inputUserSelf, transaction.getPeer(rawPeerId), rawPeerId)
            } else {
                return (apiInputUser(peer), peer, peer.id)
            }
        }
        |> mapToSignal { inputUser, maybePeer, peerId -> Signal<Bool, NoError> in
            if let inputUser = inputUser {
                return network.request(Api.functions.users.getFullUser(id: inputUser))
                |> retryRequest
                |> mapToSignal { result -> Signal<Bool, NoError> in
                    return postbox.transaction { transaction -> Bool in
                        switch result {
                        case let .userFull(userFull):
                            if let telegramUser = TelegramUser.merge(transaction.getPeer(userFull.user.peerId) as? TelegramUser, rhs: userFull.user) {
                                updatePeers(transaction: transaction, peers: [telegramUser], update: { _, updated -> Peer in
                                    return updated
                                })
                            }
                            transaction.updateCurrentPeerNotificationSettings([peerId: TelegramPeerNotificationSettings(apiSettings: userFull.notifySettings)])
                            if let presence = TelegramUserPresence(apiUser: userFull.user) {
                                updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: [userFull.user.peerId: presence])
                            }
                        }
                        transaction.updatePeerCachedData(peerIds: [peerId], update: { peerId, current in
                            let previous: CachedUserData
                            if let current = current as? CachedUserData {
                                previous = current
                            } else {
                                previous = CachedUserData()
                            }
                            switch result {
                                case let .userFull(userFull):
                                    let botInfo = userFull.botInfo.flatMap(BotInfo.init(apiBotInfo:))
                                    let isBlocked = (userFull.flags & (1 << 0)) != 0
                                    let voiceCallsAvailable = (userFull.flags & (1 << 4)) != 0
                                    var videoCallsAvailable = (userFull.flags & (1 << 13)) != 0
                                    #if DEBUG
                                    videoCallsAvailable = true
                                    #endif
                                    let callsPrivate = (userFull.flags & (1 << 5)) != 0
                                    let canPinMessages = (userFull.flags & (1 << 7)) != 0
                                    let pinnedMessageId = userFull.pinnedMsgId.flatMap({ MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: $0) })
                                    
                                    let peerStatusSettings = PeerStatusSettings(apiSettings: userFull.settings)
                                    
                                    let hasScheduledMessages = (userFull.flags & 1 << 12) != 0
                                    
                                    let autoremoveTimeout: CachedPeerAutoremoveTimeout = .known(CachedPeerAutoremoveTimeout.Value(userFull.ttlPeriod))
                                
                                    return previous.withUpdatedAbout(userFull.about).withUpdatedBotInfo(botInfo).withUpdatedCommonGroupCount(userFull.commonChatsCount).withUpdatedIsBlocked(isBlocked).withUpdatedVoiceCallsAvailable(voiceCallsAvailable).withUpdatedVideoCallsAvailable(videoCallsAvailable).withUpdatedCallsPrivate(callsPrivate).withUpdatedCanPinMessages(canPinMessages).withUpdatedPeerStatusSettings(peerStatusSettings).withUpdatedPinnedMessageId(pinnedMessageId).withUpdatedHasScheduledMessages(hasScheduledMessages)
                                        .withUpdatedAutoremoveTimeout(autoremoveTimeout)
                                        .withUpdatedThemeEmoticon(userFull.themeEmoticon)
                            }
                        })
                        return true
                    }
                }
            } else if peerId.namespace == Namespaces.Peer.CloudGroup {
                return network.request(Api.functions.messages.getFullChat(chatId: peerId.id._internalGetInt32Value()))
                |> retryRequest
                |> mapToSignal { result -> Signal<Bool, NoError> in
                    return postbox.transaction { transaction -> Bool in
                        switch result {
                        case let .chatFull(fullChat, chats, users):
                            switch fullChat {
                            case let .chatFull(chatFull):
                                transaction.updateCurrentPeerNotificationSettings([peerId: TelegramPeerNotificationSettings(apiSettings: chatFull.notifySettings)])
                            case .channelFull:
                                break
                            }
                            
                            switch fullChat {
                            case let .chatFull(chatFull):
                                var botInfos: [CachedPeerBotInfo] = []
                                for botInfo in chatFull.botInfo ?? [] {
                                    switch botInfo {
                                    case let .botInfo(userId, _, _):
                                        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt32Value(userId))
                                        let parsedBotInfo = BotInfo(apiBotInfo: botInfo)
                                        botInfos.append(CachedPeerBotInfo(peerId: peerId, botInfo: parsedBotInfo))
                                    }
                                }
                                let participants = CachedGroupParticipants(apiParticipants: chatFull.participants)
                                
                                var invitedBy: PeerId?
                                if let participants = participants {
                                    for participant in participants.participants {
                                        if participant.peerId == accountPeerId {
                                            if participant.invitedBy != accountPeerId {
                                                invitedBy = participant.invitedBy
                                            }
                                            break
                                        }
                                    }
                                }
                                
                                let photo: TelegramMediaImage? = chatFull.chatPhoto.flatMap(telegramMediaImageFromApiPhoto)
                                
                                let exportedInvitation = chatFull.exportedInvite.flatMap { ExportedInvitation(apiExportedInvite: $0) }
                                let pinnedMessageId = chatFull.pinnedMsgId.flatMap({ MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: $0) })
                            
                                var peers: [Peer] = []
                                var peerPresences: [PeerId: PeerPresence] = [:]
                                for chat in chats {
                                    if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                        peers.append(groupOrChannel)
                                    }
                                }
                                for user in users {
                                    if let telegramUser = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
                                        peers.append(telegramUser)
                                        if let presence = TelegramUserPresence(apiUser: user) {
                                            peerPresences[telegramUser.id] = presence
                                        }
                                    }
                                }
                                
                                updatePeers(transaction: transaction, peers: peers, update: { _, updated -> Peer in
                                    return updated
                                })
                                
                                updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: peerPresences)
                                
                                var flags = CachedGroupFlags()
                                if (chatFull.flags & 1 << 7) != 0 {
                                    flags.insert(.canChangeUsername)
                                }
                                
                                var hasScheduledMessages = false
                                if (chatFull.flags & 1 << 8) != 0 {
                                    hasScheduledMessages = true
                                }
                                                                
                                let groupCallDefaultJoinAs = chatFull.groupcallDefaultJoinAs
                                
                                transaction.updatePeerCachedData(peerIds: [peerId], update: { _, current in
                                    let previous: CachedGroupData
                                    if let current = current as? CachedGroupData {
                                        previous = current
                                    } else {
                                        previous = CachedGroupData()
                                    }
                                    
                                    var updatedActiveCall: CachedChannelData.ActiveCall?
                                    if let inputCall = chatFull.call {
                                        switch inputCall {
                                        case let .inputGroupCall(id, accessHash):
                                            updatedActiveCall = CachedChannelData.ActiveCall(id: id, accessHash: accessHash, title: previous.activeCall?.title, scheduleTimestamp: previous.activeCall?.scheduleTimestamp, subscribedToScheduled: previous.activeCall?.subscribedToScheduled ?? false)
                                        }
                                    }
                                    
                                    return previous.withUpdatedParticipants(participants)
                                        .withUpdatedExportedInvitation(exportedInvitation)
                                        .withUpdatedBotInfos(botInfos)
                                        .withUpdatedPinnedMessageId(pinnedMessageId)
                                        .withUpdatedAbout(chatFull.about)
                                        .withUpdatedFlags(flags)
                                        .withUpdatedHasScheduledMessages(hasScheduledMessages)
                                        .withUpdatedInvitedBy(invitedBy)
                                        .withUpdatedPhoto(photo)
                                        .withUpdatedActiveCall(updatedActiveCall)
                                        .withUpdatedCallJoinPeerId(groupCallDefaultJoinAs?.peerId)
                                        .withUpdatedThemeEmoticon(chatFull.themeEmoticon)
                                })
                            case .channelFull:
                                break
                            }
                        }
                        return true
                    }
                }
            } else if let inputChannel = maybePeer.flatMap(apiInputChannel) {
                let fullChannelSignal = network.request(Api.functions.channels.getFullChannel(channel: inputChannel))
                |> map(Optional.init)
                |> `catch` { error -> Signal<Api.messages.ChatFull?, NoError> in
                    if error.errorDescription == "CHANNEL_PRIVATE" {
                        return .single(nil)
                    }
                    return .single(nil)
                }
                let participantSignal = network.request(Api.functions.channels.getParticipant(channel: inputChannel, participant: .inputPeerSelf))
                |> map(Optional.init)
                |> `catch` { error -> Signal<Api.channels.ChannelParticipant?, NoError> in
                    return .single(nil)
                }
                
                return combineLatest(fullChannelSignal, participantSignal)
                |> mapToSignal { result, participantResult -> Signal<Bool, NoError> in
                    return postbox.transaction { transaction -> Bool in
                        if let result = result {
                            switch result {
                                case let .chatFull(fullChat, chats, users):
                                    switch fullChat {
                                        case let .channelFull(channelFull):
                                            transaction.updateCurrentPeerNotificationSettings([peerId: TelegramPeerNotificationSettings(apiSettings: channelFull.notifySettings)])
                                        case .chatFull:
                                            break
                                    }
                                    
                                    switch fullChat {
                                        case let .channelFull(flags, _, about, participantsCount, adminsCount, kickedCount, bannedCount, _, _, _, _, chatPhoto, _, apiExportedInvite, apiBotInfos, migratedFromChatId, migratedFromMaxId, pinnedMsgId, stickerSet, minAvailableMsgId, folderId, linkedChatId, location, slowmodeSeconds, slowmodeNextSendDate, statsDc, pts, inputCall, ttl, pendingSuggestions, groupcallDefaultJoinAs, themeEmoticon):
                                            var channelFlags = CachedChannelFlags()
                                            if (flags & (1 << 3)) != 0 {
                                                channelFlags.insert(.canDisplayParticipants)
                                            }
                                            if (flags & (1 << 6)) != 0 {
                                                channelFlags.insert(.canChangeUsername)
                                            }
                                            if (flags & (1 << 10)) == 0 {
                                                channelFlags.insert(.preHistoryEnabled)
                                            }
                                            if (flags & (1 << 20)) != 0 {
                                                channelFlags.insert(.canViewStats)
                                            }
                                            if (flags & (1 << 7)) != 0 {
                                                channelFlags.insert(.canSetStickerSet)
                                            }
                                            if (flags & (1 << 16)) != 0 {
                                                channelFlags.insert(.canChangePeerGeoLocation)
                                            }
                                            
                                            let linkedDiscussionPeerId: PeerId?
                                            if let linkedChatId = linkedChatId, linkedChatId != 0 {
                                                linkedDiscussionPeerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt32Value(linkedChatId))
                                            } else {
                                                linkedDiscussionPeerId = nil
                                            }

                                            let autoremoveTimeout: CachedPeerAutoremoveTimeout = .known(CachedPeerAutoremoveTimeout.Value(ttl))
                                           
                                            let peerGeoLocation: PeerGeoLocation?
                                            if let location = location {
                                                peerGeoLocation = PeerGeoLocation(apiLocation: location)
                                            } else {
                                                peerGeoLocation = nil
                                            }
                                            
                                            var botInfos: [CachedPeerBotInfo] = []
                                            for botInfo in apiBotInfos {
                                                switch botInfo {
                                                case let .botInfo(userId, _, _):
                                                    let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt32Value(userId))
                                                    let parsedBotInfo = BotInfo(apiBotInfo: botInfo)
                                                    botInfos.append(CachedPeerBotInfo(peerId: peerId, botInfo: parsedBotInfo))
                                                }
                                            }
                                            
                                            var pinnedMessageId: MessageId?
                                            if let pinnedMsgId = pinnedMsgId {
                                                pinnedMessageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: pinnedMsgId)
                                            }
                                                                                        
                                            var minAvailableMessageId: MessageId?
                                            if let minAvailableMsgId = minAvailableMsgId {
                                                minAvailableMessageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: minAvailableMsgId)
                                                
                                                if let pinnedMsgId = pinnedMsgId, pinnedMsgId < minAvailableMsgId {
                                                    pinnedMessageId = nil
                                                }
                                            }
                                            
                                            var migrationReference: ChannelMigrationReference?
                                            if let migratedFromChatId = migratedFromChatId, let migratedFromMaxId = migratedFromMaxId {
                                                migrationReference = ChannelMigrationReference(maxMessageId: MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt32Value(migratedFromChatId)), namespace: Namespaces.Message.Cloud, id: migratedFromMaxId))
                                            }
                                            
                                            var peers: [Peer] = []
                                            var peerPresences: [PeerId: PeerPresence] = [:]
                                            for chat in chats {
                                                if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                                    peers.append(groupOrChannel)
                                                }
                                            }
                                            for user in users {
                                                if let telegramUser = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
                                                    peers.append(telegramUser)
                                                    if let presence = TelegramUserPresence(apiUser: user) {
                                                        peerPresences[telegramUser.id] = presence
                                                    }
                                                }
                                            }
                                            
                                            if let participantResult = participantResult {
                                                switch participantResult {
                                                case let .channelParticipant(_, chats, users):
                                                    for user in users {
                                                        if let telegramUser = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
                                                            peers.append(telegramUser)
                                                            if let presence = TelegramUserPresence(apiUser: user) {
                                                                peerPresences[telegramUser.id] = presence
                                                            }
                                                        }
                                                    }
                                                    for chat in chats {
                                                        if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                                                            peers.append(groupOrChannel)
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            updatePeers(transaction: transaction, peers: peers, update: { _, updated -> Peer in
                                                return updated
                                            })
                                            
                                            updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: peerPresences)
                                            
                                            let stickerPack: StickerPackCollectionInfo? = stickerSet.flatMap { apiSet -> StickerPackCollectionInfo in
                                                let namespace: ItemCollectionId.Namespace
                                                switch apiSet {
                                                    case let .stickerSet(flags, _, _, _, _, _, _, _, _, _, _):
                                                        if (flags & (1 << 3)) != 0 {
                                                            namespace = Namespaces.ItemCollection.CloudMaskPacks
                                                        } else {
                                                            namespace = Namespaces.ItemCollection.CloudStickerPacks
                                                        }
                                                }
                                                
                                                return StickerPackCollectionInfo(apiSet: apiSet, namespace: namespace)
                                            }
                                            
                                            var hasScheduledMessages = false
                                            if (flags & (1 << 19)) != 0 {
                                                hasScheduledMessages = true
                                            }
                                            
                                            var invitedBy: PeerId?
                                            if let participantResult = participantResult {
                                                switch participantResult {
                                                case let.channelParticipant(participant, _, _):
                                                    switch participant {
                                                    case let .channelParticipantSelf(_, inviterId, _):
                                                        invitedBy = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt32Value(inviterId))
                                                    default:
                                                        break
                                                    }
                                                }
                                            }
                                            
                                            let photo = telegramMediaImageFromApiPhoto(chatPhoto)
                                            
                                            var minAvailableMessageIdUpdated = false
                                            transaction.updatePeerCachedData(peerIds: [peerId], update: { _, current in
                                                var previous: CachedChannelData
                                                if let current = current as? CachedChannelData {
                                                    previous = current
                                                } else {
                                                    previous = CachedChannelData()
                                                }
                                                
                                                previous = previous.withUpdatedIsNotAccessible(false)
                                                
                                                minAvailableMessageIdUpdated = previous.minAvailableMessageId != minAvailableMessageId
                                                
                                                var updatedActiveCall: CachedChannelData.ActiveCall?
                                                if let inputCall = inputCall {
                                                    switch inputCall {
                                                    case let .inputGroupCall(id, accessHash):
                                                        updatedActiveCall = CachedChannelData.ActiveCall(id: id, accessHash: accessHash, title: previous.activeCall?.title, scheduleTimestamp: previous.activeCall?.scheduleTimestamp, subscribedToScheduled: previous.activeCall?.subscribedToScheduled ?? false)
                                                    }
                                                }
                                                
                                                return previous.withUpdatedFlags(channelFlags)
                                                    .withUpdatedAbout(about)
                                                    .withUpdatedParticipantsSummary(CachedChannelParticipantsSummary(memberCount: participantsCount, adminCount: adminsCount, bannedCount: bannedCount, kickedCount: kickedCount))
                                                    .withUpdatedExportedInvitation(apiExportedInvite.flatMap { ExportedInvitation(apiExportedInvite: $0) })
                                                    .withUpdatedBotInfos(botInfos)
                                                    .withUpdatedPinnedMessageId(pinnedMessageId)
                                                    .withUpdatedStickerPack(stickerPack)
                                                    .withUpdatedMinAvailableMessageId(minAvailableMessageId)
                                                    .withUpdatedMigrationReference(migrationReference)
                                                    .withUpdatedLinkedDiscussionPeerId(.known(linkedDiscussionPeerId))
                                                    .withUpdatedPeerGeoLocation(peerGeoLocation)
                                                    .withUpdatedSlowModeTimeout(slowmodeSeconds)
                                                    .withUpdatedSlowModeValidUntilTimestamp(slowmodeNextSendDate)
                                                    .withUpdatedHasScheduledMessages(hasScheduledMessages)
                                                    .withUpdatedStatsDatacenterId(statsDc ?? 0)
                                                    .withUpdatedInvitedBy(invitedBy)
                                                    .withUpdatedPhoto(photo)
                                                    .withUpdatedActiveCall(updatedActiveCall)
                                                    .withUpdatedCallJoinPeerId(groupcallDefaultJoinAs?.peerId)
                                                    .withUpdatedAutoremoveTimeout(autoremoveTimeout)
                                                    .withUpdatedPendingSuggestions(pendingSuggestions ?? [])
                                                    .withUpdatedThemeEmoticon(themeEmoticon)
                                            })
                                        
                                            if let minAvailableMessageId = minAvailableMessageId, minAvailableMessageIdUpdated {
                                                var resourceIds: [WrappedMediaResourceId] = []
                                                transaction.deleteMessagesInRange(peerId: peerId, namespace: minAvailableMessageId.namespace, minId: 1, maxId: minAvailableMessageId.id, forEachMedia: { media in
                                                    addMessageMediaResourceIdsToRemove(media: media, resourceIds: &resourceIds)
                                                })
                                                if !resourceIds.isEmpty {
                                                    let _ = postbox.mediaBox.removeCachedResources(Set(resourceIds)).start()
                                                }
                                            }
                                        case .chatFull:
                                            break
                                    }
                            }
                        } else {
                            transaction.updatePeerCachedData(peerIds: [peerId], update: { _, _ in
                                var updated = CachedChannelData()
                                updated = updated.withUpdatedIsNotAccessible(true)
                                return updated
                            })
                        }
                        return true
                    }
                }
            } else {
                return .single(false)
            }
        }
    }
}

extension CachedPeerAutoremoveTimeout.Value {
    init?(_ apiValue: Int32?) {
        if let value = apiValue {
            self.init(peerValue: value)
        } else {
            return nil
        }
    }
}
