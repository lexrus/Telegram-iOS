import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextSelectionNode
import ReactionSelectionNode
import TelegramCore
import SwiftSignalKit

private let animationDurationFactor: Double = 1.0

public protocol ContextControllerProtocol {
    var useComplexItemsTransitionAnimation: Bool { get set }
    var immediateItemsTransitionAnimation: Bool { get set }
    
    func setItems(_ items: Signal<[ContextMenuItem], NoError>)
    func dismiss(completion: (() -> Void)?)
}

public enum ContextMenuActionItemTextLayout {
    case singleLine
    case twoLinesMax
    case secondLineWithValue(String)
}

public enum ContextMenuActionItemTextColor {
    case primary
    case destructive
}

public enum ContextMenuActionResult {
    case `default`
    case dismissWithoutContent
    case custom(ContainedViewLayoutTransition)
}

public enum ContextMenuActionItemFont {
    case regular
    case custom(UIFont)
}

public struct ContextMenuActionItemIconSource {
    public let size: CGSize
    public let signal: Signal<UIImage?, NoError>
    
    public init(size: CGSize, signal: Signal<UIImage?, NoError>) {
        self.size = size
        self.signal = signal
    }
}

public enum ContextMenuActionBadgeColor {
    case accent
    case inactive
}

public struct ContextMenuActionBadge {
    public var value: String
    public var color: ContextMenuActionBadgeColor
    
    public init(value: String, color: ContextMenuActionBadgeColor) {
        self.value = value
        self.color = color
    }
}

public final class ContextMenuActionItem {
    public let text: String
    public let textColor: ContextMenuActionItemTextColor
    public let textFont: ContextMenuActionItemFont
    public let textLayout: ContextMenuActionItemTextLayout
    public let badge: ContextMenuActionBadge?
    public let icon: (PresentationTheme) -> UIImage?
    public let iconSource: ContextMenuActionItemIconSource?
    public let action: (ContextControllerProtocol, @escaping (ContextMenuActionResult) -> Void) -> Void
    
    public init(text: String, textColor: ContextMenuActionItemTextColor = .primary, textLayout: ContextMenuActionItemTextLayout = .twoLinesMax, textFont: ContextMenuActionItemFont = .regular, badge: ContextMenuActionBadge? = nil, icon: @escaping (PresentationTheme) -> UIImage?, iconSource: ContextMenuActionItemIconSource? = nil, action: @escaping (ContextControllerProtocol, @escaping (ContextMenuActionResult) -> Void) -> Void) {
        self.text = text
        self.textColor = textColor
        self.textFont = textFont
        self.textLayout = textLayout
        self.badge = badge
        self.icon = icon
        self.iconSource = iconSource
        self.action = action
    }
}

public protocol ContextMenuCustomNode: ASDisplayNode {
    func updateLayout(constrainedWidth: CGFloat) -> (CGSize, (CGSize, ContainedViewLayoutTransition) -> Void)
    func updateTheme(presentationData: PresentationData)
}

public protocol ContextMenuCustomItem {
    func node(presentationData: PresentationData, getController: @escaping () -> ContextControllerProtocol?, actionSelected: @escaping (ContextMenuActionResult) -> Void) -> ContextMenuCustomNode
}

public enum ContextMenuItem {
    case action(ContextMenuActionItem)
    case custom(ContextMenuCustomItem, Bool)
    case separator
}

private func convertFrame(_ frame: CGRect, from fromView: UIView, to toView: UIView) -> CGRect {
    let sourceWindowFrame = fromView.convert(frame, to: nil)
    var targetWindowFrame = toView.convert(sourceWindowFrame, from: nil)
    
    if let fromWindow = fromView.window, let toWindow = toView.window {
        targetWindowFrame.origin.x += toWindow.bounds.width - fromWindow.bounds.width
    }
    return targetWindowFrame
}

private final class ContextControllerNode: ViewControllerTracingNode, UIScrollViewDelegate {
    private var presentationData: PresentationData
    private let source: ContextContentSource
    private var items: Signal<[ContextMenuItem], NoError>
    private let beginDismiss: (ContextMenuActionResult) -> Void
    private let reactionSelected: (ReactionContextItem.Reaction) -> Void
    private let beganAnimatingOut: () -> Void
    private let attemptTransitionControllerIntoNavigation: () -> Void
    fileprivate var dismissedForCancel: (() -> Void)?
    private let getController: () -> ContextControllerProtocol?
    private weak var gesture: ContextGesture?
    private var displayTextSelectionTip: Bool
    
    private var didSetItemsReady = false
    let itemsReady = Promise<Bool>()
    let contentReady = Promise<Bool>()
    
    private var currentItems: [ContextMenuItem]?
    
    private var validLayout: ContainerViewLayout?
    
    private let effectView: UIVisualEffectView
    private var propertyAnimator: AnyObject?
    private var displayLinkAnimator: DisplayLinkAnimator?
    private let dimNode: ASDisplayNode
    private let withoutBlurDimNode: ASDisplayNode
    private let dismissNode: ASDisplayNode
    private let dismissAccessibilityArea: AccessibilityAreaNode
    
    private let clippingNode: ASDisplayNode
    private let scrollNode: ASScrollNode
    
    private var originalProjectedContentViewFrame: (CGRect, CGRect)?
    private var contentAreaInScreenSpace: CGRect?
    private let contentContainerNode: ContextContentContainerNode
    private var actionsContainerNode: ContextActionsContainerNode
    private var reactionContextNode: ReactionContextNode?
    private var reactionContextNodeIsAnimatingOut = false
    
    private var didCompleteAnimationIn = false
    private var initialContinueGesturePoint: CGPoint?
    private var didMoveFromInitialGesturePoint = false
    private var highlightedActionNode: ContextActionNodeProtocol?
    private var highlightedReaction: ReactionContextItem.Reaction?
    
    private let hapticFeedback = HapticFeedback()
    
    private var animatedIn = false
    private var isAnimatingOut = false
    
    private let itemsDisposable = MetaDisposable()
    
    private let blurBackground: Bool
    
    init(account: Account, controller: ContextController, presentationData: PresentationData, source: ContextContentSource, items: Signal<[ContextMenuItem], NoError>, reactionItems: [ReactionContextItem], beginDismiss: @escaping (ContextMenuActionResult) -> Void, recognizer: TapLongTapOrDoubleTapGestureRecognizer?, gesture: ContextGesture?, reactionSelected: @escaping (ReactionContextItem.Reaction) -> Void, beganAnimatingOut: @escaping () -> Void, attemptTransitionControllerIntoNavigation: @escaping () -> Void, displayTextSelectionTip: Bool) {
        self.presentationData = presentationData
        self.source = source
        self.items = items
        self.beginDismiss = beginDismiss
        self.reactionSelected = reactionSelected
        self.beganAnimatingOut = beganAnimatingOut
        self.attemptTransitionControllerIntoNavigation = attemptTransitionControllerIntoNavigation
        self.gesture = gesture
        self.displayTextSelectionTip = displayTextSelectionTip
        
        self.getController = { [weak controller] in
            return controller
        }
        
        self.effectView = UIVisualEffectView()
        if #available(iOS 9.0, *) {
        } else {
            if presentationData.theme.rootController.keyboardColor == .dark {
                self.effectView.effect = UIBlurEffect(style: .dark)
            } else {
                self.effectView.effect = UIBlurEffect(style: .light)
            }
            self.effectView.alpha = 0.0
        }
        
        self.dimNode = ASDisplayNode()
        self.dimNode.backgroundColor = presentationData.theme.contextMenu.dimColor
        self.dimNode.alpha = 0.0
        
        self.withoutBlurDimNode = ASDisplayNode()
        self.withoutBlurDimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        self.withoutBlurDimNode.alpha = 0.0
        
        self.dismissNode = ASDisplayNode()
        self.dismissAccessibilityArea = AccessibilityAreaNode()
        self.dismissAccessibilityArea.accessibilityLabel = presentationData.strings.VoiceOver_DismissContextMenu
        self.dismissAccessibilityArea.accessibilityTraits = .button
        
        self.clippingNode = ASDisplayNode()
        self.clippingNode.clipsToBounds = true
        
        self.scrollNode = ASScrollNode()
        self.scrollNode.canCancelAllTouchesInViews = true
        self.scrollNode.view.delaysContentTouches = false
        self.scrollNode.view.showsVerticalScrollIndicator = false
        if #available(iOS 11.0, *) {
            self.scrollNode.view.contentInsetAdjustmentBehavior = .never
        }
        
        self.contentContainerNode = ContextContentContainerNode()
        
        var feedbackTap: (() -> Void)?
        
        var blurBackground = true
        if case .reference = source {
            blurBackground = false
        } else if case let .extracted(extractedSource) = source, !extractedSource.blurBackground {
            blurBackground = false
        }
        self.blurBackground = blurBackground
            
        self.actionsContainerNode = ContextActionsContainerNode(presentationData: presentationData, items: [], getController: { [weak controller] in
            return controller
        }, actionSelected: { result in
            beginDismiss(result)
        }, feedbackTap: {
            feedbackTap?()
        }, displayTextSelectionTip: self.displayTextSelectionTip, blurBackground: blurBackground)
        
        if !reactionItems.isEmpty {
            let reactionContextNode = ReactionContextNode(account: account, theme: presentationData.theme, items: reactionItems)
            self.reactionContextNode = reactionContextNode
        } else {
            self.reactionContextNode = nil
        }
        
        super.init()
        
        feedbackTap = { [weak self] in
            self?.hapticFeedback.tap()
        }
        
        self.scrollNode.view.delegate = self
        
        if blurBackground {
            self.view.addSubview(self.effectView)
            self.addSubnode(self.dimNode)
            self.addSubnode(self.withoutBlurDimNode)
        }
        
        self.addSubnode(self.clippingNode)
        
        self.clippingNode.addSubnode(self.scrollNode)
        self.scrollNode.addSubnode(self.dismissNode)
        self.scrollNode.addSubnode(self.dismissAccessibilityArea)
        
        self.scrollNode.addSubnode(self.actionsContainerNode)
        self.reactionContextNode.flatMap(self.addSubnode)
        
        if let recognizer = recognizer {
            recognizer.externalUpdated = { [weak self, weak recognizer] view, point in
                guard let strongSelf = self, let _ = recognizer else {
                    return
                }
                let localPoint = strongSelf.view.convert(point, from: view)
                let initialPoint: CGPoint
                if let current = strongSelf.initialContinueGesturePoint {
                    initialPoint = current
                } else {
                    initialPoint = localPoint
                    strongSelf.initialContinueGesturePoint = localPoint
                }
                if strongSelf.didCompleteAnimationIn {
                    if !strongSelf.didMoveFromInitialGesturePoint {
                        let distance = abs(localPoint.y - initialPoint.y)
                        if distance > 12.0 {
                            strongSelf.didMoveFromInitialGesturePoint = true
                        }
                    }
                    if strongSelf.didMoveFromInitialGesturePoint {
                        let actionPoint = strongSelf.view.convert(localPoint, to: strongSelf.actionsContainerNode.view)
                        let actionNode = strongSelf.actionsContainerNode.actionNode(at: actionPoint)
                        if strongSelf.highlightedActionNode !== actionNode {
                            strongSelf.highlightedActionNode?.setIsHighlighted(false)
                            strongSelf.highlightedActionNode = actionNode
                            if let actionNode = actionNode {
                                actionNode.setIsHighlighted(true)
                                strongSelf.hapticFeedback.tap()
                            }
                        }
                        
                        if let reactionContextNode = strongSelf.reactionContextNode {
                            let highlightedReaction = reactionContextNode.reaction(at: strongSelf.view.convert(localPoint, to: reactionContextNode.view)).flatMap { value -> ReactionContextItem.Reaction? in
                                switch value {
                                case .like:
                                    return .like
                                case .unlike:
                                    return .unlike
                                }
                            }
                            if strongSelf.highlightedReaction != highlightedReaction {
                                strongSelf.highlightedReaction = highlightedReaction
                                reactionContextNode.setHighlightedReaction(highlightedReaction)
                                if let _ = highlightedReaction {
                                    strongSelf.hapticFeedback.tap()
                                }
                            }
                        }
                    }
                }
            }
            recognizer.externalEnded = { [weak self, weak recognizer] viewAndPoint in
                guard let strongSelf = self, let recognizer = recognizer else {
                    return
                }
                recognizer.externalUpdated = nil
                if strongSelf.didMoveFromInitialGesturePoint {
                    if let (_, _) = viewAndPoint {
                        if let highlightedActionNode = strongSelf.highlightedActionNode {
                            strongSelf.highlightedActionNode = nil
                            highlightedActionNode.performAction()
                        }
                        if let _ = strongSelf.reactionContextNode {
                            if let reaction = strongSelf.highlightedReaction {
                                strongSelf.reactionSelected(reaction)
                            }
                        }
                    } else {
                        if let highlightedActionNode = strongSelf.highlightedActionNode {
                            strongSelf.highlightedActionNode = nil
                            highlightedActionNode.setIsHighlighted(false)
                        }
                        if let reactionContextNode = strongSelf.reactionContextNode, let _ = strongSelf.highlightedReaction {
                            strongSelf.highlightedReaction = nil
                            reactionContextNode.setHighlightedReaction(nil)
                        }
                    }
                }
            }
        } else if let gesture = gesture {
            gesture.externalUpdated = { [weak self, weak gesture] view, point in
                guard let strongSelf = self, let _ = gesture else {
                    return
                }
                let localPoint = strongSelf.view.convert(point, from: view)
                let initialPoint: CGPoint
                if let current = strongSelf.initialContinueGesturePoint {
                    initialPoint = current
                } else {
                    initialPoint = localPoint
                    strongSelf.initialContinueGesturePoint = localPoint
                }
                if strongSelf.didCompleteAnimationIn {
                    if !strongSelf.didMoveFromInitialGesturePoint {
                        let distance = abs(localPoint.y - initialPoint.y)
                        if distance > 4.0 {
                            strongSelf.didMoveFromInitialGesturePoint = true
                        }
                    }
                    if strongSelf.didMoveFromInitialGesturePoint {
                        let actionPoint = strongSelf.view.convert(localPoint, to: strongSelf.actionsContainerNode.view)
                        let actionNode = strongSelf.actionsContainerNode.actionNode(at: actionPoint)
                        if strongSelf.highlightedActionNode !== actionNode {
                            strongSelf.highlightedActionNode?.setIsHighlighted(false)
                            strongSelf.highlightedActionNode = actionNode
                            if let actionNode = actionNode {
                                actionNode.setIsHighlighted(true)
                                strongSelf.hapticFeedback.tap()
                            }
                        }
                        
                        if let reactionContextNode = strongSelf.reactionContextNode {
                            let highlightedReaction = reactionContextNode.reaction(at: strongSelf.view.convert(localPoint, to: reactionContextNode.view)).flatMap { value -> ReactionContextItem.Reaction? in
                                switch value {
                                case .like:
                                    return .like
                                case .unlike:
                                    return .unlike
                                }
                            }
                            if strongSelf.highlightedReaction != highlightedReaction {
                                strongSelf.highlightedReaction = highlightedReaction
                                reactionContextNode.setHighlightedReaction(highlightedReaction)
                                if let _ = highlightedReaction {
                                    strongSelf.hapticFeedback.tap()
                                }
                            }
                        }
                    }
                }
            }
            gesture.externalEnded = { [weak self, weak gesture] viewAndPoint in
                guard let strongSelf = self, let gesture = gesture else {
                    return
                }
                gesture.externalUpdated = nil
                if strongSelf.didMoveFromInitialGesturePoint {
                    if let (_, _) = viewAndPoint {
                        if let highlightedActionNode = strongSelf.highlightedActionNode {
                            strongSelf.highlightedActionNode = nil
                            highlightedActionNode.performAction()
                        }
                        if let _ = strongSelf.reactionContextNode {
                            if let reaction = strongSelf.highlightedReaction {
                                strongSelf.reactionSelected(reaction)
                            }
                        }
                    } else {
                        if let highlightedActionNode = strongSelf.highlightedActionNode {
                            strongSelf.highlightedActionNode = nil
                            highlightedActionNode.setIsHighlighted(false)
                        }
                        if let reactionContextNode = strongSelf.reactionContextNode, let _ = strongSelf.highlightedReaction {
                            strongSelf.highlightedReaction = nil
                            reactionContextNode.setHighlightedReaction(nil)
                        }
                    }
                }
            }
        }
        
        if let reactionContextNode = self.reactionContextNode {
            reactionContextNode.reactionSelected = { [weak self] reaction in
                guard let _ = self else {
                    return
                }
                switch reaction {
                case .like:
                    reactionSelected(.like)
                case .unlike:
                    reactionSelected(.unlike)
                }
            }
        }
        
        self.itemsDisposable.set((items
        |> deliverOnMainQueue).start(next: { [weak self] items in
            self?.setItems(items: items)
        }))
        
        switch source {
        case .reference, .extracted:
            self.contentReady.set(.single(true))
        case let .controller(source):
            self.contentReady.set(source.controller.ready.get())
        }
        
        self.initializeContent()
        
        self.dismissAccessibilityArea.activate = { [weak self] in
            self?.dimNodeTapped()
            return true
        }
    }
    
    deinit {
        if let propertyAnimator = self.propertyAnimator {
            if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
                let propertyAnimator = propertyAnimator as? UIViewPropertyAnimator
                propertyAnimator?.stopAnimation(true)
            }
        }
        
        self.itemsDisposable.dispose()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.dismissNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimNodeTapped)))
    }
    
    @objc private func dimNodeTapped() {
        guard self.animatedIn else {
            return
        }
        self.dismissedForCancel?()
        self.beginDismiss(.default)
    }
    
    private func initializeContent() {
        switch self.source {
        case let .reference(source):
            let transitionInfo = source.transitionInfo()
            if let transitionInfo = transitionInfo {
                let referenceNode = transitionInfo.referenceNode
                self.contentContainerNode.contentNode = .reference(node: referenceNode)
                self.contentAreaInScreenSpace = transitionInfo.contentAreaInScreenSpace
                let projectedFrame = convertFrame(referenceNode.view.bounds, from: referenceNode.view, to: self.view)
                self.originalProjectedContentViewFrame = (projectedFrame, projectedFrame)
            }
        case let .extracted(source):
            let takenViewInfo = source.takeView()
            
            if let takenViewInfo = takenViewInfo, let parentSupernode = takenViewInfo.contentContainingNode.supernode {
                self.contentContainerNode.contentNode = .extracted(node: takenViewInfo.contentContainingNode, keepInPlace: source.keepInPlace)
                if source.keepInPlace || takenViewInfo.maskView != nil {
                    self.clippingNode.view.mask = takenViewInfo.maskView
                    self.clippingNode.addSubnode(self.contentContainerNode)
                } else {
                    self.scrollNode.addSubnode(self.contentContainerNode)
                }
                let contentParentNode = takenViewInfo.contentContainingNode
                takenViewInfo.contentContainingNode.layoutUpdated = { [weak contentParentNode, weak self] size in
                    guard let strongSelf = self, let contentParentNode = contentParentNode, let parentSupernode = contentParentNode.supernode else {
                        return
                    }
                    if strongSelf.isAnimatingOut {
                        return
                    }
                    strongSelf.originalProjectedContentViewFrame = (convertFrame(contentParentNode.frame, from: parentSupernode.view, to: strongSelf.view), convertFrame(contentParentNode.contentRect, from: contentParentNode.view, to: strongSelf.view))
                    if let validLayout = strongSelf.validLayout {
                        strongSelf.updateLayout(layout: validLayout, transition: .animated(duration: 0.2 * animationDurationFactor, curve: .easeInOut), previousActionsContainerNode: nil)
                    }
                }
                takenViewInfo.contentContainingNode.updateDistractionFreeMode = { [weak self] value in
                    guard let strongSelf = self, let reactionContextNode = strongSelf.reactionContextNode else {
                        return
                    }
                    if value {
                        if !reactionContextNode.alpha.isZero {
                            reactionContextNode.alpha = 0.0
                            reactionContextNode.allowsGroupOpacity = true
                            reactionContextNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3 * animationDurationFactor, completion: { [weak reactionContextNode] _ in
                                reactionContextNode?.allowsGroupOpacity = false
                            })
                        }
                    } else if reactionContextNode.alpha != 1.0 {
                        reactionContextNode.alpha = 1.0
                        reactionContextNode.allowsGroupOpacity = true
                        reactionContextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3 * animationDurationFactor, completion: { [weak reactionContextNode] _ in
                            reactionContextNode?.allowsGroupOpacity = false
                        })
                    }
                }
                
                self.contentAreaInScreenSpace = takenViewInfo.contentAreaInScreenSpace
                self.contentContainerNode.addSubnode(takenViewInfo.contentContainingNode.contentNode)
                takenViewInfo.contentContainingNode.isExtractedToContextPreview = true
                takenViewInfo.contentContainingNode.isExtractedToContextPreviewUpdated?(true)
                
                self.originalProjectedContentViewFrame = (convertFrame(takenViewInfo.contentContainingNode.frame, from: parentSupernode.view, to: self.view), convertFrame(takenViewInfo.contentContainingNode.contentRect, from: takenViewInfo.contentContainingNode.view, to: self.view))
            }
        case let .controller(source):
            let transitionInfo = source.transitionInfo()
            if let transitionInfo = transitionInfo, let (sourceNode, sourceNodeRect) = transitionInfo.sourceNode() {
                let contentParentNode = ContextControllerContentNode(sourceNode: sourceNode, controller: source.controller, tapped: { [weak self] in
                    self?.attemptTransitionControllerIntoNavigation()
                })
                self.contentContainerNode.contentNode = .controller(contentParentNode)
                self.scrollNode.addSubnode(self.contentContainerNode)
                self.contentContainerNode.clipsToBounds = true
                self.contentContainerNode.cornerRadius = 14.0
                self.contentContainerNode.addSubnode(contentParentNode)
                
                let projectedFrame = convertFrame(sourceNodeRect, from: sourceNode.view, to: self.view)
                self.originalProjectedContentViewFrame = (projectedFrame, projectedFrame)
            }
        }
    }
    
    func animateIn() {
        self.gesture?.endPressedAppearance()
        
        self.hapticFeedback.impact()
        
        switch self.source {
            case .reference:
                break
        case .extracted:
            if let contentAreaInScreenSpace = self.contentAreaInScreenSpace, let maybeContentNode = self.contentContainerNode.contentNode, case .extracted = maybeContentNode {
                var updatedContentAreaInScreenSpace = contentAreaInScreenSpace
                updatedContentAreaInScreenSpace.origin.x = 0.0
                updatedContentAreaInScreenSpace.size.width = self.bounds.width
                
                self.clippingNode.layer.animateFrame(from: updatedContentAreaInScreenSpace, to: self.clippingNode.frame, duration: 0.18 * animationDurationFactor, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue)
                self.clippingNode.layer.animateBoundsOriginYAdditive(from: updatedContentAreaInScreenSpace.minY, to: 0.0, duration: 0.18 * animationDurationFactor, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue)
            }
        case let .controller(source):
            let transitionInfo = source.transitionInfo()
            if let transitionInfo = transitionInfo, let (sourceNode, sourceNodeRect) = transitionInfo.sourceNode() {
                let projectedFrame = convertFrame(sourceNodeRect, from: sourceNode.view, to: self.view)
                self.originalProjectedContentViewFrame = (projectedFrame, projectedFrame)
                
                var updatedContentAreaInScreenSpace = transitionInfo.contentAreaInScreenSpace
                updatedContentAreaInScreenSpace.origin.x = 0.0
                updatedContentAreaInScreenSpace.size.width = self.bounds.width
                self.contentAreaInScreenSpace = updatedContentAreaInScreenSpace
            }
        }
        
        if let validLayout = self.validLayout {
            self.updateLayout(layout: validLayout, transition: .immediate, previousActionsContainerNode: nil)
        }
        
        if !self.dimNode.isHidden {
            self.dimNode.alpha = 1.0
            self.dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor)
        } else {
            self.withoutBlurDimNode.alpha = 1.0
            self.withoutBlurDimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor)
        }
        
        if #available(iOS 10.0, *) {
            if let propertyAnimator = self.propertyAnimator {
                let propertyAnimator = propertyAnimator as? UIViewPropertyAnimator
                propertyAnimator?.stopAnimation(true)
            }
            self.effectView.effect = makeCustomZoomBlurEffect(isLight: presentationData.theme.rootController.keyboardColor == .light)
            self.effectView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor)
            self.propertyAnimator = UIViewPropertyAnimator(duration: 0.2 * animationDurationFactor * UIView.animationDurationFactor(), curve: .easeInOut, animations: {
            })
        }
        
        if let _ = self.propertyAnimator {
            if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
                self.displayLinkAnimator = DisplayLinkAnimator(duration: 0.2 * animationDurationFactor * UIView.animationDurationFactor(), from: 0.0, to: 1.0, update: { [weak self] value in
                    (self?.propertyAnimator as? UIViewPropertyAnimator)?.fractionComplete = value
                }, completion: { [weak self] in
                    self?.didCompleteAnimationIn = true
                    self?.hapticFeedback.prepareTap()
                    self?.actionsContainerNode.animateIn()
                })
            }
        } else {
            UIView.animate(withDuration: 0.2 * animationDurationFactor, animations: {
                self.effectView.effect = makeCustomZoomBlurEffect(isLight: self.presentationData.theme.rootController.keyboardColor == .light)
            }, completion: { [weak self] _ in
                self?.didCompleteAnimationIn = true
                self?.actionsContainerNode.animateIn()
            })
        }
        
        if let contentNode = self.contentContainerNode.contentNode {
            switch contentNode {
            case .reference:
                let springDuration: Double = 0.42 * animationDurationFactor
                let springDamping: CGFloat = 104.0
                
                self.actionsContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor)
                self.actionsContainerNode.layer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
                
                if let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                    let localSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.scrollNode.view)
                    
                    let localContentSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.contentContainerNode.view.superview)
                    
                    self.actionsContainerNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: localSourceFrame.center.x - self.actionsContainerNode.position.x, y: localSourceFrame.center.y - self.actionsContainerNode.position.y)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, additive: true)
                    let contentContainerOffset = CGPoint(x: localContentSourceFrame.center.x - self.contentContainerNode.frame.center.x, y: localContentSourceFrame.center.y - self.contentContainerNode.frame.center.y)
                    self.contentContainerNode.layer.animateSpring(from: NSValue(cgPoint: contentContainerOffset), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, additive: true, completion: { [weak self] _ in
                        self?.animatedIn = true
                    })
                }
            case let .extracted(extracted, keepInPlace):
                let springDuration: Double = 0.42 * animationDurationFactor
                var springDamping: CGFloat = 104.0
                if case let .extracted(source) = self.source, source.centerVertically {
                    springDamping = 124.0
                }
                
                self.actionsContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor)
                self.actionsContainerNode.layer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
                 
                if let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                    let contentParentNode = extracted
                    let localSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.scrollNode.view)
                   
                    var actionsDuration = springDuration
                    var actionsOffset: CGFloat = 0.0
                    var contentDuration = springDuration
                    if case let .extracted(source) = self.source, source.centerVertically {
                        actionsOffset = -(originalProjectedContentViewFrame.1.height - originalProjectedContentViewFrame.0.height) * 0.57
                        actionsDuration *= 1.0
                        contentDuration *= 0.9
                    }
                    
                    let localContentSourceFrame: CGRect
                    if keepInPlace {
                        localContentSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.contentContainerNode.view.superview)
                    } else {
                        localContentSourceFrame = localSourceFrame
                    }
                    
                    if let reactionContextNode = self.reactionContextNode {
                        reactionContextNode.animateIn(from: CGRect(origin: CGPoint(x: originalProjectedContentViewFrame.1.minX, y: originalProjectedContentViewFrame.1.minY), size: contentParentNode.contentRect.size))
                    }
                    
                    self.actionsContainerNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: localSourceFrame.center.x - self.actionsContainerNode.position.x, y: localSourceFrame.center.y - self.actionsContainerNode.position.y + actionsOffset)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: actionsDuration, initialVelocity: 0.0, damping: springDamping, additive: true)
                    let contentContainerOffset = CGPoint(x: localContentSourceFrame.center.x - self.contentContainerNode.frame.center.x - contentParentNode.contentRect.minX, y: localContentSourceFrame.center.y - self.contentContainerNode.frame.center.y - contentParentNode.contentRect.minY)
                    self.contentContainerNode.layer.animateSpring(from: NSValue(cgPoint: contentContainerOffset), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: contentDuration, initialVelocity: 0.0, damping: springDamping, additive: true, completion: { [weak self] _ in
                        self?.clippingNode.view.mask = nil
                        self?.animatedIn = true
                    })
                    contentParentNode.applyAbsoluteOffsetSpring?(-contentContainerOffset.y, springDuration, springDamping)
                }
                
                extracted.willUpdateIsExtractedToContextPreview?(true, .animated(duration: 0.2, curve: .easeInOut))
            case .controller:
                let springDuration: Double = 0.52 * animationDurationFactor
                let springDamping: CGFloat = 110.0
                
                self.actionsContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor)
                self.actionsContainerNode.layer.animateSpring(from: 0.1 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
                self.contentContainerNode.allowsGroupOpacity = true
                self.contentContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2 * animationDurationFactor, completion: { [weak self] _ in
                    self?.contentContainerNode.allowsGroupOpacity = false
                })
                
                if let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                    let localSourceFrame = self.view.convert(CGRect(origin: CGPoint(x: originalProjectedContentViewFrame.1.minX, y: originalProjectedContentViewFrame.1.minY), size: CGSize(width: originalProjectedContentViewFrame.1.width, height: originalProjectedContentViewFrame.1.height)), to: self.scrollNode.view)
                    
                    self.contentContainerNode.layer.animateSpring(from: min(localSourceFrame.width / self.contentContainerNode.frame.width, localSourceFrame.height / self.contentContainerNode.frame.height) as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: springDuration, initialVelocity: 0.0, damping: springDamping)
                    
                    switch self.source {
                    case let .controller(controller):
                        controller.animatedIn()
                    default:
                        break
                    }
                    
                    let contentContainerOffset = CGPoint(x: localSourceFrame.center.x - self.contentContainerNode.frame.center.x, y: localSourceFrame.center.y - self.contentContainerNode.frame.center.y)
                    if let contentNode = self.contentContainerNode.contentNode, case let .controller(controller) = contentNode {
                        let snapshotView: UIView? = nil// controller.sourceNode.view.snapshotContentTree()
                        if let snapshotView = snapshotView {
                            controller.sourceNode.isHidden = true
                            
                            self.view.insertSubview(snapshotView, belowSubview: self.contentContainerNode.view)
                            snapshotView.layer.animateSpring(from: NSValue(cgPoint: localSourceFrame.center), to: NSValue(cgPoint: CGPoint(x: self.contentContainerNode.frame.midX, y: self.contentContainerNode.frame.minY + localSourceFrame.height / 2.0)), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false)
                            //snapshotView.layer.animateSpring(from: 1.0 as NSNumber, to: (self.contentContainerNode.frame.width / localSourceFrame.width) as NSNumber, keyPath: "transform.scale", duration: springDuration, initialVelocity: 0.0, damping: springDamping, removeOnCompletion: false)
                            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2 * animationDurationFactor, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                                snapshotView?.removeFromSuperview()
                            })
                        }
                    }
                    self.actionsContainerNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: localSourceFrame.center.x - self.actionsContainerNode.position.x, y: localSourceFrame.center.y - self.actionsContainerNode.position.y)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, additive: true)
                    self.contentContainerNode.layer.animateSpring(from: NSValue(cgPoint: contentContainerOffset), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: springDuration, initialVelocity: 0.0, damping: springDamping, additive: true, completion: { [weak self] _ in
                        self?.animatedIn = true
                    })
                }
            }
        }
    }
    
    func animateOut(result initialResult: ContextMenuActionResult, completion: @escaping () -> Void) {
        self.isUserInteractionEnabled = false
        
        self.beganAnimatingOut()
        
        var transitionDuration: Double = 0.2
        var transitionCurve: ContainedViewLayoutTransitionCurve = .easeInOut
        
        var result = initialResult
        
        switch self.source {
        case let .reference(source):
            guard let maybeContentNode = self.contentContainerNode.contentNode, case let .reference(referenceNode) = maybeContentNode else {
                return
            }
            
            let transitionInfo = source.transitionInfo()
            if transitionInfo == nil {
                result = .dismissWithoutContent
            }
            
            switch result {
            case let .custom(value):
                switch value {
                case let .animated(duration, curve):
                    transitionDuration = duration
                    transitionCurve = curve
                default:
                    break
                }
            default:
                break
            }
            
            self.isUserInteractionEnabled = false
            self.isAnimatingOut = true
            
            self.scrollNode.view.setContentOffset(self.scrollNode.view.contentOffset, animated: false)
            
            if let transitionInfo = transitionInfo, let parentSupernode = referenceNode.supernode {
                self.originalProjectedContentViewFrame = (convertFrame(referenceNode.frame, from: parentSupernode.view, to: self.view), convertFrame(referenceNode.bounds, from: referenceNode.view, to: self.view))
                
                var updatedContentAreaInScreenSpace = transitionInfo.contentAreaInScreenSpace
                updatedContentAreaInScreenSpace.origin.x = 0.0
                updatedContentAreaInScreenSpace.size.width = self.bounds.width
                
                self.clippingNode.layer.animateFrame(from: self.clippingNode.frame, to: updatedContentAreaInScreenSpace, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
                self.clippingNode.layer.animateBoundsOriginYAdditive(from: 0.0, to: updatedContentAreaInScreenSpace.minY, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
            }
                                    
            if !self.dimNode.isHidden {
                self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false)
            } else {
                self.withoutBlurDimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false)
            }
            
            self.actionsContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15 * animationDurationFactor, removeOnCompletion: false, completion: { _ in
                completion()
            })
            self.actionsContainerNode.layer.animateScale(from: 1.0, to: 0.1, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
            
            let animateOutToItem: Bool
            switch result {
            case .default, .custom:
                animateOutToItem = true
            case .dismissWithoutContent:
                animateOutToItem = false
            }
            
            if animateOutToItem, let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                let localSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.scrollNode.view)
                self.actionsContainerNode.layer.animatePosition(from: CGPoint(), to: CGPoint(x: localSourceFrame.center.x - self.actionsContainerNode.position.x, y: localSourceFrame.center.y - self.actionsContainerNode.position.y), duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false, additive: true)
            }
        case let .extracted(source):
            guard let maybeContentNode = self.contentContainerNode.contentNode, case let .extracted(contentParentNode, keepInPlace) = maybeContentNode else {
                return
            }
            
            let putBackInfo = source.putBack()
            
            if putBackInfo == nil {
                result = .dismissWithoutContent
            }
            
            switch result {
            case let .custom(value):
                switch value {
                case let .animated(duration, curve):
                    transitionDuration = duration
                    transitionCurve = curve
                default:
                    break
                }
            default:
                break
            }
            
            self.isUserInteractionEnabled = false
            self.isAnimatingOut = true
            
            self.scrollNode.view.setContentOffset(self.scrollNode.view.contentOffset, animated: false)
            
            var completedEffect = false
            var completedContentNode = false
            var completedActionsNode = false
            
            if let putBackInfo = putBackInfo, let parentSupernode = contentParentNode.supernode {
                self.originalProjectedContentViewFrame = (convertFrame(contentParentNode.frame, from: parentSupernode.view, to: self.view), convertFrame(contentParentNode.contentRect, from: contentParentNode.view, to: self.view))
                
                var updatedContentAreaInScreenSpace = putBackInfo.contentAreaInScreenSpace
                updatedContentAreaInScreenSpace.origin.x = 0.0
                updatedContentAreaInScreenSpace.size.width = self.bounds.width
                
                self.clippingNode.view.mask = putBackInfo.maskView
                self.clippingNode.layer.animateFrame(from: self.clippingNode.frame, to: updatedContentAreaInScreenSpace, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
                self.clippingNode.layer.animateBoundsOriginYAdditive(from: 0.0, to: updatedContentAreaInScreenSpace.minY, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
            }
            
            let intermediateCompletion: () -> Void = { [weak self, weak contentParentNode] in
                if completedEffect && completedContentNode && completedActionsNode {
                    switch result {
                    case .default, .custom:
                        if let contentParentNode = contentParentNode {
                            contentParentNode.addSubnode(contentParentNode.contentNode)
                            contentParentNode.isExtractedToContextPreview = false
                            contentParentNode.isExtractedToContextPreviewUpdated?(false)
                        }
                    case .dismissWithoutContent:
                        break
                    }
                    
                    self?.clippingNode.view.mask = nil
                    
                    completion()
                }
            }
            
            if #available(iOS 10.0, *) {
                if let propertyAnimator = self.propertyAnimator {
                    let propertyAnimator = propertyAnimator as? UIViewPropertyAnimator
                    propertyAnimator?.stopAnimation(true)
                }
                self.propertyAnimator = UIViewPropertyAnimator(duration: transitionDuration * UIView.animationDurationFactor(), curve: .easeInOut, animations: {
                    //self?.effectView.effect = nil
                })
            }
            
            if let _ = self.propertyAnimator {
                if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
                    self.displayLinkAnimator = DisplayLinkAnimator(duration: 0.2 * animationDurationFactor * UIView.animationDurationFactor(), from: 0.0, to: 0.999, update: { [weak self] value in
                        (self?.propertyAnimator as? UIViewPropertyAnimator)?.fractionComplete = value
                    }, completion: {
                        completedEffect = true
                        intermediateCompletion()
                    })
                }
                self.effectView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2 * animationDurationFactor, delay: 0.0, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false)
            } else {
                UIView.animate(withDuration: 0.21 * animationDurationFactor, animations: {
                    if #available(iOS 9.0, *) {
                        self.effectView.effect = nil
                    } else {
                        self.effectView.alpha = 0.0
                    }
                }, completion: { _ in
                    completedEffect = true
                    intermediateCompletion()
                })
            }
            
            if !self.dimNode.isHidden {
                self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false)
            } else {
                self.withoutBlurDimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false)
            }
            
            self.actionsContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15 * animationDurationFactor, removeOnCompletion: false, completion: { _ in
                completedActionsNode = true
                intermediateCompletion()
            })
            self.actionsContainerNode.layer.animateScale(from: 1.0, to: 0.1, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
            
            let animateOutToItem: Bool
            switch result {
            case .default, .custom:
                animateOutToItem = true
            case .dismissWithoutContent:
                animateOutToItem = false
            }
            
            if animateOutToItem, let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                let localSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.scrollNode.view)
                let localContentSourceFrame: CGRect
                if keepInPlace {
                    localContentSourceFrame = self.view.convert(originalProjectedContentViewFrame.1, to: self.contentContainerNode.view.superview)
                } else {
                    localContentSourceFrame = localSourceFrame
                }
                
                var actionsOffset: CGFloat = 0.0
                if case let .extracted(source) = self.source, source.centerVertically {
                    actionsOffset = -localSourceFrame.width * 0.6
                }
                
                self.actionsContainerNode.layer.animatePosition(from: CGPoint(), to: CGPoint(x: localSourceFrame.center.x - self.actionsContainerNode.position.x, y: localSourceFrame.center.y - self.actionsContainerNode.position.y + actionsOffset), duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false, additive: true)
                let contentContainerOffset = CGPoint(x: localContentSourceFrame.center.x - self.contentContainerNode.frame.center.x - contentParentNode.contentRect.minX, y: localContentSourceFrame.center.y - self.contentContainerNode.frame.center.y - contentParentNode.contentRect.minY)
                self.contentContainerNode.layer.animatePosition(from: CGPoint(), to: contentContainerOffset, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false, additive: true, completion: { _ in
                    completedContentNode = true
                    intermediateCompletion()
                })
                contentParentNode.updateAbsoluteRect?(self.contentContainerNode.frame.offsetBy(dx: 0.0, dy: -self.scrollNode.view.contentOffset.y + contentContainerOffset.y), self.bounds.size)
                contentParentNode.applyAbsoluteOffset?(CGPoint(x: 0.0, y: -contentContainerOffset.y), transitionCurve, transitionDuration)
                
                if let reactionContextNode = self.reactionContextNode {
                    reactionContextNode.animateOut(to: CGRect(origin: CGPoint(x: originalProjectedContentViewFrame.1.minX, y: originalProjectedContentViewFrame.1.minY), size: contentParentNode.contentRect.size), animatingOutToReaction: self.reactionContextNodeIsAnimatingOut)
                }
                
                contentParentNode.willUpdateIsExtractedToContextPreview?(false, .animated(duration: 0.2, curve: .easeInOut))
            } else {
                if let snapshotView = contentParentNode.contentNode.view.snapshotContentTree(keepTransform: true) {
                    self.contentContainerNode.view.addSubview(snapshotView)
                }
                
                contentParentNode.addSubnode(contentParentNode.contentNode)
                contentParentNode.isExtractedToContextPreview = false
                contentParentNode.isExtractedToContextPreviewUpdated?(false)
                
                self.contentContainerNode.allowsGroupOpacity = true
                self.contentContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false, completion: { _ in
                    completedContentNode = true
                    intermediateCompletion()
                })
                
                contentParentNode.contentNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                contentParentNode.willUpdateIsExtractedToContextPreview?(false, .animated(duration: 0.2, curve: .easeInOut))
                
                if let reactionContextNode = self.reactionContextNode {
                    reactionContextNode.animateOut(to: nil, animatingOutToReaction: self.reactionContextNodeIsAnimatingOut)
                }
            }
        case let .controller(source):
            guard let maybeContentNode = self.contentContainerNode.contentNode, case let .controller(controller) = maybeContentNode else {
                return
            }
            
            let transitionInfo = source.transitionInfo()
            
            if transitionInfo == nil {
                result = .dismissWithoutContent
            }
            
            switch result {
            case let .custom(value):
                switch value {
                case let .animated(duration, curve):
                    transitionDuration = duration
                    transitionCurve = curve
                default:
                    break
                }
            default:
                break
            }
            
            self.isUserInteractionEnabled = false
            self.isAnimatingOut = true
            
            self.scrollNode.view.setContentOffset(self.scrollNode.view.contentOffset, animated: false)
            
            var completedEffect = false
            var completedContentNode = false
            var completedActionsNode = false
            
            if let transitionInfo = transitionInfo, let (sourceNode, sourceNodeRect) = transitionInfo.sourceNode() {
                let projectedFrame = convertFrame(sourceNodeRect, from: sourceNode.view, to: self.view)
                self.originalProjectedContentViewFrame = (projectedFrame, projectedFrame)
                
                var updatedContentAreaInScreenSpace = transitionInfo.contentAreaInScreenSpace
                updatedContentAreaInScreenSpace.origin.x = 0.0
                updatedContentAreaInScreenSpace.size.width = self.bounds.width
            }
            
            let intermediateCompletion: () -> Void = {
                if completedEffect && completedContentNode && completedActionsNode {
                    switch result {
                    case .default, .custom:
                        break
                    case .dismissWithoutContent:
                        break
                    }
                    
                    completion()
                }
            }
            
            if #available(iOS 10.0, *) {
                if let propertyAnimator = self.propertyAnimator {
                    let propertyAnimator = propertyAnimator as? UIViewPropertyAnimator
                    propertyAnimator?.stopAnimation(true)
                }
                self.propertyAnimator = UIViewPropertyAnimator(duration: transitionDuration * UIView.animationDurationFactor(), curve: .easeInOut, animations: { [weak self] in
                    self?.effectView.effect = nil
                })
            }
            
            if let _ = self.propertyAnimator {
                if #available(iOSApplicationExtension 10.0, iOS 10.0, *) {
                    self.displayLinkAnimator = DisplayLinkAnimator(duration: 0.2 * animationDurationFactor * UIView.animationDurationFactor(), from: 0.0, to: 0.999, update: { [weak self] value in
                        (self?.propertyAnimator as? UIViewPropertyAnimator)?.fractionComplete = value
                    }, completion: {
                        completedEffect = true
                        intermediateCompletion()
                    })
                }
                self.effectView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.05 * animationDurationFactor, delay: 0.15, timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, removeOnCompletion: false)
            } else {
                UIView.animate(withDuration: 0.21 * animationDurationFactor, animations: {
                    if #available(iOS 9.0, *) {
                        self.effectView.effect = nil
                    } else {
                        self.effectView.alpha = 0.0
                    }
                }, completion: { _ in
                    completedEffect = true
                    intermediateCompletion()
                })
            }
            
            if !self.dimNode.isHidden {
                self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false)
            } else {
                self.withoutBlurDimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false)
            }
            self.actionsContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2 * animationDurationFactor, removeOnCompletion: false, completion: { _ in
                completedActionsNode = true
                intermediateCompletion()
            })
            self.contentContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2 * animationDurationFactor, removeOnCompletion: false, completion: { _ in
            })
            self.actionsContainerNode.layer.animateScale(from: 1.0, to: 0.1, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
            self.contentContainerNode.layer.animateScale(from: 1.0, to: 0.01, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false)
            
            let animateOutToItem: Bool
            switch result {
            case .default, .custom:
                animateOutToItem = true
            case .dismissWithoutContent:
                animateOutToItem = false
            }
            
            if animateOutToItem, let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                
                let localSourceFrame = self.view.convert(CGRect(origin: CGPoint(x: originalProjectedContentViewFrame.1.minX, y: originalProjectedContentViewFrame.1.minY), size: CGSize(width: originalProjectedContentViewFrame.1.width, height: originalProjectedContentViewFrame.1.height)), to: self.scrollNode.view)
                
                self.actionsContainerNode.layer.animatePosition(from: CGPoint(), to: CGPoint(x: localSourceFrame.center.x - self.actionsContainerNode.position.x, y: localSourceFrame.center.y - self.actionsContainerNode.position.y), duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false, additive: true)
                let contentContainerOffset = CGPoint(x: localSourceFrame.center.x - self.contentContainerNode.frame.center.x, y: localSourceFrame.center.y - self.contentContainerNode.frame.center.y)
                self.contentContainerNode.layer.animatePosition(from: CGPoint(), to: contentContainerOffset, duration: transitionDuration * animationDurationFactor, timingFunction: transitionCurve.timingFunction, removeOnCompletion: false, additive: true, completion: { [weak self] _ in
                    completedContentNode = true
                    if let strongSelf = self, let contentNode = strongSelf.contentContainerNode.contentNode, case let .controller(controller) = contentNode {
                        controller.sourceNode.isHidden = false
                    }
                    intermediateCompletion()
                })
            } else {
                if let contentNode = self.contentContainerNode.contentNode, case let .controller(controller) = contentNode {
                    controller.sourceNode.isHidden = false
                }
                
                if let snapshotView = controller.view.snapshotContentTree(keepTransform: true) {
                    self.contentContainerNode.view.addSubview(snapshotView)
                }
                
                self.contentContainerNode.allowsGroupOpacity = true
                self.contentContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: transitionDuration * animationDurationFactor, removeOnCompletion: false, completion: { _ in
                    completedContentNode = true
                    intermediateCompletion()
                })
                
                if let reactionContextNode = self.reactionContextNode {
                    reactionContextNode.animateOut(to: nil, animatingOutToReaction: self.reactionContextNodeIsAnimatingOut)
                }
            }
        }
    }
    
    func animateOutToReaction(value: String, targetEmptyNode: ASDisplayNode, targetFilledNode: ASDisplayNode, hideNode: Bool, completion: @escaping () -> Void) {
        guard let reactionContextNode = self.reactionContextNode else {
            self.animateOut(result: .default, completion: completion)
            return
        }
        var contentCompleted = false
        var reactionCompleted = false
        let intermediateCompletion: () -> Void = {
            if contentCompleted && reactionCompleted {
                completion()
            }
        }
        
        self.reactionContextNodeIsAnimatingOut = true
        self.animateOut(result: .default, completion: {
            contentCompleted = true
            intermediateCompletion()
        })
        reactionContextNode.animateOutToReaction(value: value, targetEmptyNode: targetEmptyNode, targetFilledNode: targetFilledNode, hideNode: hideNode, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.reactionContextNode?.removeFromSupernode()
            strongSelf.reactionContextNode = nil
            reactionCompleted = true
            intermediateCompletion()
        })
    }
    
    func setItemsSignal(items: Signal<[ContextMenuItem], NoError>) {
        self.items = items
        self.itemsDisposable.set((items
        |> deliverOnMainQueue).start(next: { [weak self] items in
            guard let strongSelf = self else {
                return
            }
            strongSelf.setItems(items: items)
        }))
    }
    
    private func setItems(items: [ContextMenuItem]) {
        if let _ = self.currentItems, !self.didCompleteAnimationIn && self.getController()?.immediateItemsTransitionAnimation == true {
            return
        }
        
        self.currentItems = items
        
        let previousActionsContainerNode = self.actionsContainerNode
        self.actionsContainerNode = ContextActionsContainerNode(presentationData: self.presentationData, items: items, getController: { [weak self] in
            return self?.getController()
        }, actionSelected: { [weak self] result in
            self?.beginDismiss(result)
        }, feedbackTap: { [weak self] in
            self?.hapticFeedback.tap()
        }, displayTextSelectionTip: self.displayTextSelectionTip, blurBackground: self.blurBackground)
        self.scrollNode.insertSubnode(self.actionsContainerNode, aboveSubnode: previousActionsContainerNode)
        
        if let layout = self.validLayout {
            self.updateLayout(layout: layout, transition: .animated(duration: 0.3, curve: .spring), previousActionsContainerNode: previousActionsContainerNode)
        } else {
            previousActionsContainerNode.removeFromSupernode()
        }
        
        if !self.didSetItemsReady {
            self.didSetItemsReady = true
            self.displayTextSelectionTip = false
            self.itemsReady.set(.single(true))
        }
    }
    
    func updateTheme(presentationData: PresentationData) {
        self.presentationData = presentationData
        
        self.dimNode.backgroundColor = presentationData.theme.contextMenu.dimColor
        self.actionsContainerNode.updateTheme(presentationData: presentationData)
        
        if let validLayout = self.validLayout {
            self.updateLayout(layout: validLayout, transition: .immediate, previousActionsContainerNode: nil)
        }
    }
    
    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition, previousActionsContainerNode: ContextActionsContainerNode?) {
        if self.isAnimatingOut {
            return
        }
        
        self.validLayout = layout
        
        var actionsContainerTransition = transition
        if previousActionsContainerNode != nil {
            actionsContainerTransition = .immediate
        }
        
        transition.updateFrame(view: self.effectView, frame: CGRect(origin: CGPoint(), size: layout.size))
        transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        transition.updateFrame(node: self.withoutBlurDimNode, frame: CGRect(origin: CGPoint(), size: layout.size))

        switch layout.metrics.widthClass {
        case .compact:
            if case .reference = self.source {
            } else if case let .extracted(extractedSource) = self.source, !extractedSource.blurBackground {
            } else if self.effectView.superview == nil {
                self.view.insertSubview(self.effectView, at: 0)
                if #available(iOS 10.0, *) {
                    if let propertyAnimator = self.propertyAnimator {
                        let propertyAnimator = propertyAnimator as? UIViewPropertyAnimator
                        propertyAnimator?.stopAnimation(true)
                    }
                }
                self.effectView.effect = makeCustomZoomBlurEffect(isLight: presentationData.theme.rootController.keyboardColor == .light)
                self.dimNode.alpha = 1.0
            }
            self.dimNode.isHidden = false
            self.withoutBlurDimNode.isHidden = true
        case .regular:
            if case .reference = self.source {
            } else if case let .extracted(extractedSource) = self.source, !extractedSource.blurBackground {
            } else if self.effectView.superview != nil {
                self.effectView.removeFromSuperview()
                self.withoutBlurDimNode.alpha = 1.0
            }
            self.dimNode.isHidden = true
            self.withoutBlurDimNode.isHidden = false
        }
        transition.updateFrame(node: self.clippingNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        
        transition.updateFrame(node: self.scrollNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        
        let actionsSideInset: CGFloat = layout.safeInsets.left + 11.0
        var contentTopInset: CGFloat = max(11.0, layout.statusBarHeight ?? 0.0)
        if let _ = self.reactionContextNode {
            contentTopInset += 34.0
        }
        let actionsBottomInset: CGFloat = 11.0
        
        if let contentNode = self.contentContainerNode.contentNode {
            switch contentNode {
            case let .reference(referenceNode):
                let contentActionsSpacing: CGFloat = 8.0
                if let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                    let isInitialLayout = self.actionsContainerNode.frame.size.width.isZero
                    let previousContainerFrame = self.view.convert(self.contentContainerNode.frame, from: self.scrollNode.view)
                    
                    let actionsSize = self.actionsContainerNode.updateLayout(widthClass: layout.metrics.widthClass, constrainedWidth: layout.size.width - actionsSideInset * 2.0, transition: actionsContainerTransition)
                    self.actionsContainerNode.updateSize(containerSize: actionsSize, contentSize: actionsSize)
                    let contentSize = originalProjectedContentViewFrame.1.size
                    self.contentContainerNode.updateLayout(size: contentSize, scaledSize: contentSize, transition: transition)
                    
                    let maximumActionsFrameOrigin = max(60.0, layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - actionsSize.height)
                     
                    let originalActionsY = min(originalProjectedContentViewFrame.1.maxY + contentActionsSpacing, maximumActionsFrameOrigin)
                    let preferredActionsX = originalProjectedContentViewFrame.1.minX
                    
                    var originalActionsFrame = CGRect(origin: CGPoint(x: max(actionsSideInset, min(layout.size.width - actionsSize.width - actionsSideInset, preferredActionsX)), y: originalActionsY), size: actionsSize)
                    let originalContentX: CGFloat = originalProjectedContentViewFrame.1.minX
                    let originalContentY = originalProjectedContentViewFrame.1.minY

                    var originalContentFrame = CGRect(origin: CGPoint(x: originalContentX, y: originalContentY), size: originalProjectedContentViewFrame.1.size)
                    let topEdge = max(contentTopInset, self.contentAreaInScreenSpace?.minY ?? 0.0)
                    if originalContentFrame.minY < topEdge {
                        let requiredOffset = topEdge - originalContentFrame.minY
                        let availableOffset = max(0.0, layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - originalActionsFrame.maxY)
                        let offset = min(requiredOffset, availableOffset)
                        originalActionsFrame = originalActionsFrame.offsetBy(dx: 0.0, dy: offset)
                        originalContentFrame = originalContentFrame.offsetBy(dx: 0.0, dy: offset)
                    }
                    
                    var contentHeight = max(layout.size.height, max(layout.size.height, originalActionsFrame.maxY + actionsBottomInset) - originalContentFrame.minY + contentTopInset)
                    contentHeight = max(contentHeight, actionsSize.height + originalActionsFrame.minY + actionsBottomInset)
                    
                    var overflowOffset: CGFloat
                    var contentContainerFrame: CGRect

                    overflowOffset = min(0.0, originalActionsFrame.minY - contentTopInset)
                    let contentParentNode = referenceNode
                    contentContainerFrame = originalContentFrame
                    if !overflowOffset.isZero {
                        let offsetDelta = contentParentNode.frame.height + 4.0
                        overflowOffset += offsetDelta
                        overflowOffset = min(0.0, overflowOffset)
                        
                        originalActionsFrame.origin.x -= contentParentNode.frame.width + 14.0
                        originalActionsFrame.origin.x = max(actionsSideInset, originalActionsFrame.origin.x)
                        
                        if originalActionsFrame.minX < contentContainerFrame.minX {
                            contentContainerFrame.origin.x = min(originalActionsFrame.maxX + 14.0, layout.size.width - actionsSideInset)
                        }
                        originalActionsFrame.origin.y += offsetDelta
                        if originalActionsFrame.maxY < originalContentFrame.maxY {
                            originalActionsFrame.origin.y += contentParentNode.frame.height
                            originalActionsFrame.origin.y = min(originalActionsFrame.origin.y, layout.size.height - originalActionsFrame.height - actionsBottomInset)
                        }
                        contentHeight -= offsetDelta
                    }

                    let scrollContentSize = CGSize(width: layout.size.width, height: contentHeight)
                    if self.scrollNode.view.contentSize != scrollContentSize {
                        self.scrollNode.view.contentSize = scrollContentSize
                    }
                    self.actionsContainerNode.panSelectionGestureEnabled = scrollContentSize.height <= layout.size.height
                    
                    transition.updateFrame(node: self.contentContainerNode, frame: contentContainerFrame)
                    actionsContainerTransition.updateFrame(node: self.actionsContainerNode, frame: originalActionsFrame.offsetBy(dx: 0.0, dy: -overflowOffset))
                    
                    if isInitialLayout {
                        let currentContainerFrame = self.view.convert(self.contentContainerNode.frame, from: self.scrollNode.view)
                        if overflowOffset < 0.0 {
                            transition.animateOffsetAdditive(node: self.scrollNode, offset: currentContainerFrame.minY - previousContainerFrame.minY)
                        }
                    }
                }
            case let .extracted(contentParentNode, keepInPlace):
                var centerVertically = false
                if case let .extracted(source) = self.source, source.centerVertically {
                    centerVertically = true
                }
                let contentActionsSpacing: CGFloat = keepInPlace ? 16.0 : 8.0
                if let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                    let isInitialLayout = self.actionsContainerNode.frame.size.width.isZero
                    let previousContainerFrame = self.view.convert(self.contentContainerNode.frame, from: self.scrollNode.view)
                    
                    let actionsSize = self.actionsContainerNode.updateLayout(widthClass: layout.metrics.widthClass, constrainedWidth: layout.size.width - actionsSideInset * 2.0, transition: actionsContainerTransition)
                    self.actionsContainerNode.updateSize(containerSize: actionsSize, contentSize: actionsSize)
                    let contentSize = originalProjectedContentViewFrame.1.size
                    self.contentContainerNode.updateLayout(size: contentSize, scaledSize: contentSize, transition: transition)
                    
                    let maximumActionsFrameOrigin = max(60.0, layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - actionsSize.height)
                    let preferredActionsX: CGFloat
                    let originalActionsY: CGFloat
                    if centerVertically {
                        originalActionsY = min(originalProjectedContentViewFrame.1.maxY + contentActionsSpacing, maximumActionsFrameOrigin)
                        preferredActionsX = originalProjectedContentViewFrame.1.maxX - actionsSize.width
                    } else if keepInPlace {
                        originalActionsY = originalProjectedContentViewFrame.1.minY - contentActionsSpacing - actionsSize.height
                        preferredActionsX = max(actionsSideInset, originalProjectedContentViewFrame.1.maxX - actionsSize.width)
                    } else {
                        originalActionsY = min(originalProjectedContentViewFrame.1.maxY + contentActionsSpacing, maximumActionsFrameOrigin)
                        preferredActionsX = originalProjectedContentViewFrame.1.minX
                    }

                    var originalActionsFrame = CGRect(origin: CGPoint(x: max(actionsSideInset, min(layout.size.width - actionsSize.width - actionsSideInset, preferredActionsX)), y: originalActionsY), size: actionsSize)
                    let originalContentX: CGFloat = originalProjectedContentViewFrame.1.minX
                    let originalContentY: CGFloat
                    if keepInPlace {
                        originalContentY = originalProjectedContentViewFrame.1.minY
                    } else {
                        originalContentY = originalActionsFrame.minY - contentActionsSpacing - originalProjectedContentViewFrame.1.size.height
                    }
                    var originalContentFrame = CGRect(origin: CGPoint(x: originalContentX, y: originalContentY), size: originalProjectedContentViewFrame.1.size)
                    let topEdge = max(contentTopInset, self.contentAreaInScreenSpace?.minY ?? 0.0)
                    if originalContentFrame.minY < topEdge {
                        let requiredOffset = topEdge - originalContentFrame.minY
                        let availableOffset = max(0.0, layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - originalActionsFrame.maxY)
                        let offset = min(requiredOffset, availableOffset)
                        originalActionsFrame = originalActionsFrame.offsetBy(dx: 0.0, dy: offset)
                        originalContentFrame = originalContentFrame.offsetBy(dx: 0.0, dy: offset)
                    }
                    
                    var contentHeight: CGFloat
                    if keepInPlace {
                        contentHeight = max(layout.size.height, max(layout.size.height, originalActionsFrame.maxY + actionsBottomInset) - originalActionsFrame.minY + contentTopInset)
                    } else {
                        contentHeight = max(layout.size.height, max(layout.size.height, originalActionsFrame.maxY + actionsBottomInset) - originalContentFrame.minY + contentTopInset)
                    }
                    
                    var overflowOffset: CGFloat
                    var contentContainerFrame: CGRect
                    if centerVertically {
                        overflowOffset = 0.0
                        if layout.size.width > layout.size.height, case .compact = layout.metrics.widthClass {
                            let totalWidth = originalContentFrame.width + originalActionsFrame.width + contentActionsSpacing
                            contentContainerFrame = CGRect(origin: CGPoint(x: floor((layout.size.width - totalWidth) / 2.0 + originalContentFrame.width * 0.1), y: floor((layout.size.height - originalContentFrame.height) / 2.0)), size: originalContentFrame.size)
                            originalActionsFrame.origin.x = contentContainerFrame.maxX + contentActionsSpacing + 14.0
                            originalActionsFrame.origin.y = contentContainerFrame.origin.y
                            contentHeight = layout.size.height
                        } else {
                            let totalHeight = originalContentFrame.height + originalActionsFrame.height
                            contentContainerFrame = CGRect(origin: CGPoint(x: floor((layout.size.width - originalContentFrame.width) / 2.0), y: floor((layout.size.height - totalHeight) / 2.0)), size: originalContentFrame.size)
                            originalActionsFrame.origin.y = contentContainerFrame.maxY + contentActionsSpacing
                        }
                    } else if keepInPlace {
                        overflowOffset = min(0.0, originalActionsFrame.minY - contentTopInset)
                        contentContainerFrame = originalContentFrame.offsetBy(dx: -contentParentNode.contentRect.minX, dy: -contentParentNode.contentRect.minY)
                        if !overflowOffset.isZero {
                            let offsetDelta = contentParentNode.contentRect.height + 4.0
                            overflowOffset += offsetDelta
                            overflowOffset = min(0.0, overflowOffset)
                            
                            originalActionsFrame.origin.x -= contentParentNode.contentRect.maxX - contentParentNode.contentRect.minX + 14.0
                            originalActionsFrame.origin.x = max(actionsSideInset, originalActionsFrame.origin.x)
                            //originalActionsFrame.origin.y += contentParentNode.contentRect.height
                            if originalActionsFrame.minX < contentContainerFrame.minX {
                                contentContainerFrame.origin.x = min(originalActionsFrame.maxX + 14.0, layout.size.width - actionsSideInset)
                            }
                            originalActionsFrame.origin.y += offsetDelta
                            if originalActionsFrame.maxY < originalContentFrame.maxY {
                                originalActionsFrame.origin.y += contentParentNode.contentRect.height
                                originalActionsFrame.origin.y = min(originalActionsFrame.origin.y, layout.size.height - originalActionsFrame.height - actionsBottomInset)
                            }
                            contentHeight -= offsetDelta
                        }
                    } else {
                        overflowOffset = min(0.0, originalContentFrame.minY - contentTopInset)
                        contentContainerFrame = originalContentFrame.offsetBy(dx: -contentParentNode.contentRect.minX, dy: -overflowOffset - contentParentNode.contentRect.minY)
                        
                        if contentContainerFrame.maxX > layout.size.width {
                            contentContainerFrame = CGRect(origin: CGPoint(x: layout.size.width - contentContainerFrame.width - 11.0, y: contentContainerFrame.minY), size: contentContainerFrame.size)
                        }
                    }
                    
                    let scrollContentSize = CGSize(width: layout.size.width, height: contentHeight)
                    if self.scrollNode.view.contentSize != scrollContentSize {
                        self.scrollNode.view.contentSize = scrollContentSize
                    }
                    self.actionsContainerNode.panSelectionGestureEnabled = scrollContentSize.height <= layout.size.height
                    
                    transition.updateFrame(node: self.contentContainerNode, frame: contentContainerFrame)
                    actionsContainerTransition.updateFrame(node: self.actionsContainerNode, frame: originalActionsFrame.offsetBy(dx: 0.0, dy: -overflowOffset))
                    
                    if isInitialLayout {
                        if !keepInPlace {
                            self.scrollNode.view.contentOffset = CGPoint(x: 0.0, y: -overflowOffset)
                        }
                        let currentContainerFrame = self.view.convert(self.contentContainerNode.frame, from: self.scrollNode.view)
                        if overflowOffset < 0.0 {
                            transition.animateOffsetAdditive(node: self.scrollNode, offset: currentContainerFrame.minY - previousContainerFrame.minY)
                        }
                    }
                    
                    let absoluteContentRect = contentContainerFrame.offsetBy(dx: 0.0, dy: -self.scrollNode.view.contentOffset.y)
                    
                    contentParentNode.updateAbsoluteRect?(absoluteContentRect, layout.size)
                    
                    if let reactionContextNode = self.reactionContextNode {
                        let insets = layout.insets(options: [.statusBar])
                        transition.updateFrame(node: reactionContextNode, frame: CGRect(origin: CGPoint(), size: layout.size))
                        reactionContextNode.updateLayout(size: layout.size, insets: insets, anchorRect: CGRect(origin: CGPoint(x: absoluteContentRect.minX + contentParentNode.contentRect.minX, y: absoluteContentRect.minY + contentParentNode.contentRect.minY), size: contentParentNode.contentRect.size), transition: transition)
                    }
                }
            case let .controller(contentParentNode):
                var projectedFrame: CGRect = convertFrame(contentParentNode.sourceNode.bounds, from: contentParentNode.sourceNode.view, to: self.view)
                switch self.source {
                case let .controller(source):
                    let transitionInfo = source.transitionInfo()
                    if let (sourceNode, sourceRect) = transitionInfo?.sourceNode() {
                        projectedFrame = convertFrame(sourceRect, from: sourceNode.view, to: self.view)
                    }
                default:
                    break
                }
                self.originalProjectedContentViewFrame = (projectedFrame, projectedFrame)
                
                if let originalProjectedContentViewFrame = self.originalProjectedContentViewFrame {
                    let contentActionsSpacing: CGFloat = actionsSideInset
                    let topEdge = max(contentTopInset, self.contentAreaInScreenSpace?.minY ?? 0.0)
                    
                    let isInitialLayout = self.actionsContainerNode.frame.size.width.isZero
                    let previousContainerFrame = self.view.convert(self.contentContainerNode.frame, from: self.scrollNode.view)
                    
                    let constrainedWidth: CGFloat
                    if layout.size.width < layout.size.height {
                        constrainedWidth = layout.size.width
                    } else {
                        constrainedWidth = floor(layout.size.width / 2.0)
                    }
                    
                    let actionsSize = self.actionsContainerNode.updateLayout(widthClass: layout.metrics.widthClass, constrainedWidth: constrainedWidth - actionsSideInset * 2.0, transition: actionsContainerTransition)
                    let contentScale = (constrainedWidth - actionsSideInset * 2.0) / constrainedWidth
                    var contentUnscaledSize: CGSize
                    if case .compact = layout.metrics.widthClass {
                        self.actionsContainerNode.updateSize(containerSize: actionsSize, contentSize: actionsSize)
                        
                        let proposedContentHeight: CGFloat
                        if layout.size.width < layout.size.height {
                            proposedContentHeight = layout.size.height - topEdge - contentActionsSpacing - actionsSize.height - layout.intrinsicInsets.bottom - actionsBottomInset
                        } else {
                            proposedContentHeight = layout.size.height - topEdge - topEdge
                            
                            let maxActionsHeight = layout.size.height - topEdge - topEdge
                            self.actionsContainerNode.updateSize(containerSize: CGSize(width: actionsSize.width, height: min(actionsSize.height, maxActionsHeight)), contentSize: actionsSize)
                        }
                        contentUnscaledSize = CGSize(width: constrainedWidth, height: max(100.0, proposedContentHeight))
                        
                        if let preferredSize = contentParentNode.controller.preferredContentSizeForLayout(ContainerViewLayout(size: contentUnscaledSize, metrics: LayoutMetrics(widthClass: .compact, heightClass: .compact), deviceMetrics: layout.deviceMetrics, intrinsicInsets: UIEdgeInsets(), safeInsets: UIEdgeInsets(), additionalInsets: UIEdgeInsets(), statusBarHeight: nil, inputHeight: nil, inputHeightIsInteractivellyChanging: false, inVoiceOver: false)) {
                            contentUnscaledSize = preferredSize
                        }
                    } else {
                        let maxActionsHeight = layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - actionsSize.height
                        self.actionsContainerNode.updateSize(containerSize: CGSize(width: actionsSize.width, height: min(actionsSize.height, maxActionsHeight)), contentSize: actionsSize)
                        
                        let proposedContentHeight = layout.size.height - topEdge - contentActionsSpacing - actionsSize.height - layout.intrinsicInsets.bottom - actionsBottomInset
                        contentUnscaledSize = CGSize(width: min(layout.size.width, 340.0), height: min(568.0, proposedContentHeight))
                        
                        if let preferredSize = contentParentNode.controller.preferredContentSizeForLayout(ContainerViewLayout(size: contentUnscaledSize, metrics: LayoutMetrics(widthClass: .compact, heightClass: .compact), deviceMetrics: layout.deviceMetrics, intrinsicInsets: UIEdgeInsets(), safeInsets: UIEdgeInsets(), additionalInsets: UIEdgeInsets(), statusBarHeight: nil, inputHeight: nil, inputHeightIsInteractivellyChanging: false, inVoiceOver: false)) {
                            contentUnscaledSize = preferredSize
                        }
                    }
                    let contentSize = CGSize(width: floor(contentUnscaledSize.width * contentScale), height: floor(contentUnscaledSize.height * contentScale))
                    
                    self.contentContainerNode.updateLayout(size: contentUnscaledSize, scaledSize: contentSize, transition: transition)
                    
                    let maximumActionsFrameOrigin = max(60.0, layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - actionsSize.height)
                    var originalActionsFrame: CGRect
                    var originalContentFrame: CGRect
                    var contentHeight: CGFloat
                    if case .compact = layout.metrics.widthClass {
                        if layout.size.width < layout.size.height {
                            let sideInset = floor((layout.size.width - max(contentSize.width, actionsSize.width)) / 2.0)
                            originalActionsFrame = CGRect(origin: CGPoint(x: sideInset, y: min(maximumActionsFrameOrigin, floor((layout.size.height - contentActionsSpacing - contentSize.height) / 2.0) + contentSize.height + contentActionsSpacing)), size: actionsSize)
                            originalContentFrame = CGRect(origin: CGPoint(x: sideInset, y: originalActionsFrame.minY - contentActionsSpacing - contentSize.height), size: contentSize)
                            if originalContentFrame.minY < topEdge {
                                let requiredOffset = topEdge - originalContentFrame.minY
                                let availableOffset = max(0.0, layout.size.height - layout.intrinsicInsets.bottom - actionsBottomInset - originalActionsFrame.maxY)
                                let offset = min(requiredOffset, availableOffset)
                                originalActionsFrame = originalActionsFrame.offsetBy(dx: 0.0, dy: offset)
                                originalContentFrame = originalContentFrame.offsetBy(dx: 0.0, dy: offset)
                            }
                            contentHeight = max(layout.size.height, max(layout.size.height, originalActionsFrame.maxY + actionsBottomInset) - originalContentFrame.minY + contentTopInset)
                        } else {
                            originalContentFrame = CGRect(origin: CGPoint(x: floor((layout.size.width - contentSize.width - actionsSideInset - actionsSize.width) / 2.0), y: floor((layout.size.height - contentSize.height) / 2.0)), size: contentSize)
                            originalActionsFrame = CGRect(origin: CGPoint(x: originalContentFrame.maxX + actionsSideInset, y: max(topEdge, originalContentFrame.minY)), size: actionsSize)
                            contentHeight = max(layout.size.height, max(originalContentFrame.maxY, originalActionsFrame.maxY))
                        }
                    } else {
                        originalContentFrame = CGRect(origin: CGPoint(x: floor(originalProjectedContentViewFrame.1.midX - contentSize.width / 2.0), y: floor(originalProjectedContentViewFrame.1.midY - contentSize.height / 2.0)), size: contentSize)
                        originalContentFrame.origin.x = min(originalContentFrame.origin.x, layout.size.width - actionsSideInset - contentSize.width)
                        originalContentFrame.origin.x = max(originalContentFrame.origin.x, actionsSideInset)
                        originalContentFrame.origin.y = min(originalContentFrame.origin.y, layout.size.height - layout.intrinsicInsets.bottom - actionsSideInset - contentSize.height)
                        originalContentFrame.origin.y = max(originalContentFrame.origin.y, contentTopInset)
                        if originalContentFrame.maxX <= layout.size.width - actionsSideInset - actionsSize.width - contentActionsSpacing {
                            originalActionsFrame = CGRect(origin: CGPoint(x: originalContentFrame.maxX + contentActionsSpacing, y: originalContentFrame.minY), size: actionsSize)
                            if originalActionsFrame.maxX > layout.size.width - actionsSideInset {
                                let offset = originalActionsFrame.maxX - (layout.size.width - actionsSideInset)
                                originalActionsFrame.origin.x -= offset
                                originalContentFrame.origin.x -= offset
                            }
                        } else {
                            originalActionsFrame = CGRect(origin: CGPoint(x: originalContentFrame.minX - contentActionsSpacing - actionsSize.width, y: originalContentFrame.minY), size: actionsSize)
                            if originalActionsFrame.minX < actionsSideInset {
                                let offset = actionsSideInset - originalActionsFrame.minX
                                originalActionsFrame.origin.x += offset
                                originalContentFrame.origin.x += offset
                            }
                        }
                        contentHeight = layout.size.height
                        contentHeight = max(contentHeight, originalActionsFrame.maxY + actionsBottomInset)
                        contentHeight = max(contentHeight, originalContentFrame.maxY + actionsBottomInset)
                    }
                    
                    let scrollContentSize = CGSize(width: layout.size.width, height: contentHeight)
                    if self.scrollNode.view.contentSize != scrollContentSize {
                        self.scrollNode.view.contentSize = scrollContentSize
                    }
                    self.actionsContainerNode.panSelectionGestureEnabled = true
                    
                    let overflowOffset = min(0.0, originalContentFrame.minY - contentTopInset)
                    
                    let contentContainerFrame = originalContentFrame
                    transition.updateFrame(node: self.contentContainerNode, frame: contentContainerFrame.offsetBy(dx: 0.0, dy: -overflowOffset))
                    actionsContainerTransition.updateFrame(node: self.actionsContainerNode, frame: originalActionsFrame.offsetBy(dx: 0.0, dy: -overflowOffset))
                    
                    if isInitialLayout {
                        self.scrollNode.view.contentOffset = CGPoint(x: 0.0, y: -overflowOffset)
                        let currentContainerFrame = self.view.convert(self.contentContainerNode.frame, from: self.scrollNode.view)
                        if overflowOffset < 0.0 {
                            transition.animateOffsetAdditive(node: self.scrollNode, offset: currentContainerFrame.minY - previousContainerFrame.minY)
                        }
                    }
                    
                    let absoluteContentRect = contentContainerFrame.offsetBy(dx: 0.0, dy: -self.scrollNode.view.contentOffset.y)
                    
                    if let reactionContextNode = self.reactionContextNode {
                        let insets = layout.insets(options: [.statusBar])
                        transition.updateFrame(node: reactionContextNode, frame: CGRect(origin: CGPoint(), size: layout.size))
                        reactionContextNode.updateLayout(size: layout.size, insets: insets, anchorRect: CGRect(origin: CGPoint(x: absoluteContentRect.minX, y: absoluteContentRect.minY), size: contentSize), transition: transition)
                    }
                }
            }
        }
            
        if let previousActionsContainerNode = previousActionsContainerNode {
            if transition.isAnimated && self.getController()?.immediateItemsTransitionAnimation == false {
                if previousActionsContainerNode.hasAdditionalActions && !self.actionsContainerNode.hasAdditionalActions && self.getController()?.useComplexItemsTransitionAnimation == true {
                    var initialFrame = self.actionsContainerNode.frame
                    let delta = (previousActionsContainerNode.frame.height - self.actionsContainerNode.frame.height)
                    initialFrame.origin.y = self.actionsContainerNode.frame.minY + previousActionsContainerNode.frame.height - self.actionsContainerNode.frame.height
                    transition.animateFrame(node: self.actionsContainerNode, from: initialFrame)
                    transition.animatePosition(node: previousActionsContainerNode, to: CGPoint(x: 0.0, y: -delta), removeOnCompletion: false, additive: true)
                    previousActionsContainerNode.animateOut(offset: delta, transition: transition)
                    
                    previousActionsContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak previousActionsContainerNode] _ in
                        previousActionsContainerNode?.removeFromSupernode()
                    })
                    self.actionsContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                } else {
                    transition.updateTransformScale(node: previousActionsContainerNode, scale: 0.1)
                    previousActionsContainerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak previousActionsContainerNode] _ in
                        previousActionsContainerNode?.removeFromSupernode()
                    })
                    
                    transition.animateTransformScale(node: self.actionsContainerNode, from: 0.1)
                    self.actionsContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            } else {
                previousActionsContainerNode.removeFromSupernode()
            }
        }
        
        transition.updateFrame(node: self.dismissNode, frame: CGRect(origin: CGPoint(), size: self.scrollNode.view.contentSize))
        self.dismissAccessibilityArea.frame =  CGRect(origin: CGPoint(), size: self.scrollNode.view.contentSize)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let layout = self.validLayout else {
            return
        }
        if let maybeContentNode = self.contentContainerNode.contentNode, case let .extracted(contentParentNode, keepInPlace) = maybeContentNode {
            let contentContainerFrame = self.contentContainerNode.frame
            let absoluteRect: CGRect
            if keepInPlace {
                absoluteRect = contentContainerFrame
            } else {
                absoluteRect = contentContainerFrame.offsetBy(dx: 0.0, dy: -self.scrollNode.view.contentOffset.y)
            }
            contentParentNode.updateAbsoluteRect?(absoluteRect, layout.size)
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !self.bounds.contains(point) {
            return nil
        }
        if let reactionContextNode = self.reactionContextNode {
            if let result = reactionContextNode.hitTest(self.view.convert(point, to: reactionContextNode.view), with: event) {
                return result
            }
        }
        let mappedPoint = self.view.convert(point, to: self.scrollNode.view)
        if let maybeContentNode = self.contentContainerNode.contentNode {
            switch maybeContentNode {
            case .reference:
                break
            case let .extracted(contentParentNode, _):
                if case let .extracted(source) = self.source {
                    if !source.ignoreContentTouches {
                        let contentPoint = self.view.convert(point, to: contentParentNode.contentNode.view)
                        if let result = contentParentNode.contentNode.customHitTest?(contentPoint) {
                            return result
                        } else if let result = contentParentNode.contentNode.hitTest(contentPoint, with: event) {
                            if result is TextSelectionNodeView {
                                return result
                            } else if contentParentNode.contentRect.contains(contentPoint) {
                                return contentParentNode.contentNode.view
                            }
                        }
                    }
                }
            case let .controller(controller):
                var passthrough = false
                switch self.source {
                case let .controller(controllerSource):
                    passthrough = controllerSource.passthroughTouches
                default:
                    break
                }
                if passthrough {
                    let controllerPoint = self.view.convert(point, to: controller.controller.view)
                    if let result = controller.controller.view.hitTest(controllerPoint, with: event) {
                        #if DEBUG
                        //return controller.view
                        #endif
                        return result
                    }
                }
            }
        }
        
        if self.actionsContainerNode.frame.contains(mappedPoint) {
            return self.actionsContainerNode.hitTest(self.view.convert(point, to: self.actionsContainerNode.view), with: event)
        }
        
        return self.dismissNode.view
    }
}

public final class ContextControllerReferenceViewInfo {
    public let referenceNode: ContextReferenceContentNode
    public let contentAreaInScreenSpace: CGRect
    
    public init(referenceNode: ContextReferenceContentNode, contentAreaInScreenSpace: CGRect) {
        self.referenceNode = referenceNode
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
    }
}

public protocol ContextReferenceContentSource: AnyObject {
    var shouldBeDismissed: Signal<Bool, NoError> { get }
    
    func transitionInfo() -> ContextControllerReferenceViewInfo?
}

public extension ContextReferenceContentSource {
    var shouldBeDismissed: Signal<Bool, NoError> {
        return .single(false)
    }
}

public final class ContextControllerTakeViewInfo {
    public let contentContainingNode: ContextExtractedContentContainingNode
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    
    public init(contentContainingNode: ContextExtractedContentContainingNode, contentAreaInScreenSpace: CGRect, maskView: UIView? = nil) {
        self.contentContainingNode = contentContainingNode
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.maskView = maskView
    }
}

public final class ContextControllerPutBackViewInfo {
    public let contentAreaInScreenSpace: CGRect
    public let maskView: UIView?
    
    public init(contentAreaInScreenSpace: CGRect, maskView: UIView? = nil) {
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.maskView = maskView
    }
}

public protocol ContextExtractedContentSource: AnyObject {
    var centerVertically: Bool { get }
    var keepInPlace: Bool { get }
    var ignoreContentTouches: Bool { get }
    var blurBackground: Bool { get }
    var shouldBeDismissed: Signal<Bool, NoError> { get }
    
    func takeView() -> ContextControllerTakeViewInfo?
    func putBack() -> ContextControllerPutBackViewInfo?
}

public extension ContextExtractedContentSource {
    var centerVertically: Bool {
        return false
    }

    var shouldBeDismissed: Signal<Bool, NoError> {
        return .single(false)
    }
}

public final class ContextControllerTakeControllerInfo {
    public let contentAreaInScreenSpace: CGRect
    public let sourceNode: () -> (ASDisplayNode, CGRect)?
    
    public init(contentAreaInScreenSpace: CGRect, sourceNode: @escaping () -> (ASDisplayNode, CGRect)?) {
        self.contentAreaInScreenSpace = contentAreaInScreenSpace
        self.sourceNode = sourceNode
    }
}

public protocol ContextControllerContentSource: AnyObject {
    var controller: ViewController { get }
    var navigationController: NavigationController? { get }
    var passthroughTouches: Bool { get }
    
    func transitionInfo() -> ContextControllerTakeControllerInfo?
    
    func animatedIn()
}

public enum ContextContentSource {
    case reference(ContextReferenceContentSource)
    case extracted(ContextExtractedContentSource)
    case controller(ContextControllerContentSource)
}

public final class ContextController: ViewController, StandalonePresentableController, ContextControllerProtocol {
    private let account: Account
    private var presentationData: PresentationData
    private let source: ContextContentSource
    private var items: Signal<[ContextMenuItem], NoError>
    private var reactionItems: [ReactionContextItem]
    
    private let _ready = Promise<Bool>()
    override public var ready: Promise<Bool> {
        return self._ready
    }
    
    private weak var recognizer: TapLongTapOrDoubleTapGestureRecognizer?
    private weak var gesture: ContextGesture?
    private let displayTextSelectionTip: Bool
    
    private var animatedDidAppear = false
    private var wasDismissed = false
    
    private var controllerNode: ContextControllerNode {
        return self.displayNode as! ContextControllerNode
    }
    
    public var reactionSelected: ((ReactionContextItem.Reaction) -> Void)?
    public var dismissed: (() -> Void)?
    public var dismissedForCancel: (() -> Void)? {
        didSet {
            self.controllerNode.dismissedForCancel = self.dismissedForCancel
        }
    }
    
    public var useComplexItemsTransitionAnimation = false
    public var immediateItemsTransitionAnimation = false
    
    private var shouldBeDismissedDisposable: Disposable?
    
    public init(account: Account, presentationData: PresentationData, source: ContextContentSource, items: Signal<[ContextMenuItem], NoError>, reactionItems: [ReactionContextItem], recognizer: TapLongTapOrDoubleTapGestureRecognizer? = nil, gesture: ContextGesture? = nil, displayTextSelectionTip: Bool = false) {
        self.account = account
        self.presentationData = presentationData
        self.source = source
        self.items = items
        self.reactionItems = reactionItems
        self.recognizer = recognizer
        self.gesture = gesture
        self.displayTextSelectionTip = displayTextSelectionTip
        
        super.init(navigationBarPresentationData: nil)
              
        switch source {
            case let .reference(referenceSource):
                self.statusBar.statusBarStyle = .Ignore
                
                self.shouldBeDismissedDisposable = (referenceSource.shouldBeDismissed
                |> filter { $0 }
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] _ in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.dismiss(result: .default, completion: {})
                })
            case let .extracted(extractedSource):
                if extractedSource.blurBackground {
                    self.statusBar.statusBarStyle = .Hide
                } else {
                    self.statusBar.statusBarStyle = .Ignore
                }
                self.shouldBeDismissedDisposable = (extractedSource.shouldBeDismissed
                |> filter { $0 }
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] _ in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.dismiss(result: .default, completion: {})
                })
            case .controller:
                self.statusBar.statusBarStyle = .Hide
        }

        self.lockOrientation = true
        self.blocksBackgroundWhenInOverlay = true
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.shouldBeDismissedDisposable?.dispose()
    }
    
    override public func loadDisplayNode() {
        self.displayNode = ContextControllerNode(account: self.account, controller: self, presentationData: self.presentationData, source: self.source, items: self.items, reactionItems: self.reactionItems, beginDismiss: { [weak self] result in
            self?.dismiss(result: result, completion: nil)
        }, recognizer: self.recognizer, gesture: self.gesture, reactionSelected: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            strongSelf.reactionSelected?(value)
        }, beganAnimatingOut: { [weak self] in
            self?.statusBar.statusBarStyle = .Ignore
        }, attemptTransitionControllerIntoNavigation: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            switch strongSelf.source {
            /*case let .controller(controller):
                if let navigationController = controller.navigationController {
                    strongSelf.presentingViewController?.dismiss(animated: false, completion: nil)
                    navigationController.pushViewController(controller.controller, animated: false)
                }*/
            default:
                break
            }
        }, displayTextSelectionTip: self.displayTextSelectionTip)
        self.controllerNode.dismissedForCancel = self.dismissedForCancel
        self.displayNodeDidLoad()
        
        self._ready.set(combineLatest(queue: .mainQueue(), self.controllerNode.itemsReady.get(), self.controllerNode.contentReady.get())
        |> map { values in
            return values.0 && values.1
        })
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.controllerNode.updateLayout(layout: layout, transition: transition, previousActionsContainerNode: nil)
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        if self.ignoreAppearanceMethodInvocations() {
            return
        }
        super.viewDidAppear(animated)
        
        if !self.wasDismissed && !self.animatedDidAppear {
            self.animatedDidAppear = true
            self.controllerNode.animateIn()
        }
    }
    
    public func setItems(_ items: Signal<[ContextMenuItem], NoError>) {
        self.items = items
        if self.isNodeLoaded {
            self.controllerNode.setItemsSignal(items: items)
        }
    }
    
    public func updateTheme(presentationData: PresentationData) {
        self.presentationData = presentationData
        if self.isNodeLoaded {
            self.controllerNode.updateTheme(presentationData: presentationData)
        }
    }
    
    private func dismiss(result: ContextMenuActionResult, completion: (() -> Void)?) {
        if !self.wasDismissed {
            self.wasDismissed = true
            self.controllerNode.animateOut(result: result, completion: { [weak self] in
                self?.presentingViewController?.dismiss(animated: false, completion: nil)
                completion?()
            })
            self.dismissed?()
        }
    }
    
    override public func dismiss(completion: (() -> Void)? = nil) {
        self.dismiss(result: .default, completion: completion)
    }
    
    public func dismissWithReaction(value: String, targetEmptyNode: ASDisplayNode, targetFilledNode: ASDisplayNode, hideNode: Bool, completion: (() -> Void)?) {
        if !self.wasDismissed {
            self.wasDismissed = true
            self.controllerNode.animateOutToReaction(value: value, targetEmptyNode: targetEmptyNode, targetFilledNode: targetFilledNode, hideNode: hideNode, completion: { [weak self] in
                self?.presentingViewController?.dismiss(animated: false, completion: nil)
                completion?()
            })
            self.dismissed?()
        }
    }
}
