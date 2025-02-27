import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import AccountContext

class ChatInputPanelNode: ASDisplayNode {
    var context: AccountContext?
    var interfaceInteraction: ChatPanelInterfaceInteraction?
    var prevInputPanelNode: ChatInputPanelNode?
    
    func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, additionalSideInsets: UIEdgeInsets, maxHeight: CGFloat, isSecondary: Bool, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics) -> CGFloat {
        return 0.0
    }
    
    func minimalHeight(interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics) -> CGFloat {
        return 0.0
    }
    
    func defaultHeight(metrics: LayoutMetrics) -> CGFloat {
        if case .regular = metrics.widthClass, case .regular = metrics.heightClass {
            return 49.0
        } else {
            return 45.0
        }
    }
    
    func canHandleTransition(from prevInputPanelNode: ChatInputPanelNode?) -> Bool {
        return false
    }
}
