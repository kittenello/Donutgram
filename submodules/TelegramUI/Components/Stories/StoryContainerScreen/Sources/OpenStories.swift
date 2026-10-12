import Foundation
import UIKit
import Display
import UndoUI
import AccountContext
import SwiftSignalKit
import TelegramCore
import AvatarNode
import DGSimpleSettings

public extension StoryContainerScreen {
    // The `ghostSuggestForStories` question. The openers ask it once the story
    // has loaded, before the viewer opens (see `askDonutgramStoryGhostIfNeeded`);
    // the viewer asks it itself for every other way in (see
    // `donutgramMarkAsSeen`). «Да» turns ghost mode on with story receipts
    // hidden before `answered` runs. The standard controller closes itself when
    // a button is tapped. A tap outside does nothing: closed without an answer
    // (Escape), the opener opens nothing and the viewer keeps holding its
    // receipts.
    internal static func makeDonutgramStoryGhostAlert(context: AccountContext, answered: @escaping () -> Void) -> AlertController {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        // The buttons stay tappable while the alert fades out. Only the first
        // tap counts, or an opener would push a second viewer.
        var didAnswer = false
        return standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: "Режим призрака", text: "Вы хотите включить Режим призрака перед просмотром истории?", actions: [
            TextAlertAction(type: .defaultAction, title: "Нет", action: {
                if didAnswer {
                    return
                }
                didAnswer = true
                answered()
            }),
            TextAlertAction(type: .genericAction, title: "Да", action: {
                if didAnswer {
                    return
                }
                didAnswer = true
                let settings = DGSimpleSettings.shared
                settings.ghostReadStories = false
                settings.ghostModeEnabled = true
                answered()
            })
        ], dismissOnOutsideTap: false)
    }
    
    // Ghost mode hides story views, but a live story is a group call: watching it joins
    // the call as the account, so its host can see the viewer. The viewer asks first
    // (StoryItemContentComponent). Only the first tap counts.
    internal static func makeDonutgramLiveStreamGhostAlert(context: AccountContext, completion: @escaping (Bool) -> Void) -> AlertController {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let languageCode = presentationData.strings.primaryComponent.languageCode
        var didAnswer = false
        return standardTextAlertController(theme: AlertControllerTheme(presentationData: presentationData), title: dgLocalized("Режим призрака", languageCode: languageCode), text: dgLocalized("Это прямой эфир. Смотреть его можно только как участник, и автор может увидеть вас среди зрителей.", languageCode: languageCode), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                if didAnswer {
                    return
                }
                didAnswer = true
                completion(false)
            }),
            TextAlertAction(type: .defaultAction, title: dgLocalized("Смотреть", languageCode: languageCode), action: {
                if didAnswer {
                    return
                }
                didAnswer = true
                completion(true)
            })
        ], dismissOnOutsideTap: false)
    }
    
    // Whether watching a live story has to be confirmed: ghost mode with story view
    // receipts off (the check `_internal_markStoryAsSeen` makes).
    internal static func donutgramLiveStreamNeedsGhostConfirmation() -> Bool {
        let settings = DGSimpleSettings.shared
        return settings.ghostModeEnabled && !settings.ghostReadStories
    }

    // Whether stealth mode still hides story views. Its last half minute counts
    // as over: the local deadline runs a round trip late, and the server judges
    // a receipt when it arrives.
    internal static func isDonutgramStealthModeActive(until activeUntilTimestamp: Int32?) -> Bool {
        return (activeUntilTimestamp ?? 0) - 30 > Int32(Date().timeIntervalSince1970)
    }

    // The question before a viewer opens, as the last step of the opener's
    // loading signal, so the opener's progress and cancellation cover the
    // stealth check as well. It calls `open` with whether the question was
    // answered. `open(false)` runs without a question when there is nothing to
    // ask: the setting is off, ghost mode is on, or stealth mode hides the view
    // for now (the viewer asks once it lapses). It also runs when
    // `parentController` has no window, e.g. a chat list covered by a chat:
    // `present` would show nothing there, so the viewer asks instead. `open`
    // runs on subscription when the setting is off or ghost mode is on, and on
    // a later main-queue turn otherwise. Closed without an answer (Escape),
    // nothing opens. The signal is cold: nothing runs until it is subscribed.
    static func askDonutgramStoryGhostIfNeeded(context: AccountContext, parentController: ViewController?, open: @escaping (_ answered: Bool) -> Void) -> Signal<Never, NoError> {
        return deferred { [weak parentController] () -> Signal<Never, NoError> in
            let settings = DGSimpleSettings.shared
            if !settings.ghostSuggestForStories || settings.ghostModeEnabled {
                open(false)
                return .complete()
            }
            return context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.StoryConfigurationState())
            |> deliverOnMainQueue
            |> mapToSignal { state -> Signal<Never, NoError> in
                if isDonutgramStealthModeActive(until: state.stealthModeState.activeUntilTimestamp) {
                    open(false)
                } else if let parentController, parentController.window != nil {
                    parentController.present(makeDonutgramStoryGhostAlert(context: context, answered: {
                        open(true)
                    }), in: .window(.root))
                } else {
                    open(false)
                }
                return .complete()
            }
        }
    }

    static func openArchivedStories(context: AccountContext, parentController: ViewController, avatarNode: AvatarNode, sharedProgressDisposable: MetaDisposable?) {
        let storyContent = StoryContentContextImpl(context: context, isHidden: true, focusedPeerId: nil, singlePeer: false)
        let signal = storyContent.state
        |> take(1)
        |> mapToSignal { state -> Signal<StoryContentContextState, NoError> in
            if let slice = state.slice {
                return waitUntilStoryMediaPreloaded(context: context, peerId: slice.effectivePeer.id, storyItem: slice.item.storyItem)
                |> timeout(4.0, queue: .mainQueue(), alternate: .complete())
                |> map { _ -> StoryContentContextState in
                }
                |> then(.single(state))
            } else {
                return .single(state)
            }
        }
        |> deliverOnMainQueue
        |> mapToSignal { [weak parentController, weak avatarNode] state -> Signal<Never, NoError> in
            let open: (Bool) -> Void = { answered in
                var transitionIn: StoryContainerScreen.TransitionIn?
                if let avatarNode {
                    transitionIn = StoryContainerScreen.TransitionIn(
                        sourceView: avatarNode.view,
                        sourceRect: avatarNode.view.bounds,
                        sourceCornerRadius: avatarNode.view.bounds.width * 0.5,
                        sourceIsAvatar: false
                    )
                    avatarNode.isHidden = true
                }
                
                let storyContainerScreen = StoryContainerScreen(
                    context: context,
                    content: storyContent,
                    transitionIn: transitionIn,
                    transitionOut: { peerId, _ in
                        if let avatarNode {
                            let destinationView = avatarNode.view
                            return StoryContainerScreen.TransitionOut(
                                destinationView: destinationView,
                                transitionView: StoryContainerScreen.TransitionView(
                                    makeView: { [weak destinationView] in
                                        let parentView = UIView()
                                        if let copyView = destinationView?.snapshotContentTree(unhide: true) {
                                            parentView.addSubview(copyView)
                                        }
                                        return parentView
                                    },
                                    updateView: { copyView, state, transition in
                                        guard let view = copyView.subviews.first else {
                                            return
                                        }
                                        let size = state.sourceSize.interpolate(to: state.destinationSize, amount: state.progress)
                                        transition.setPosition(view: view, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
                                        transition.setScale(view: view, scale: size.width / state.destinationSize.width)
                                    },
                                    insertCloneTransitionView: nil
                                ),
                                destinationRect: destinationView.bounds,
                                destinationCornerRadius: destinationView.bounds.width * 0.5,
                                destinationIsAvatar: false,
                                completed: { [weak avatarNode] in
                                    guard let avatarNode else {
                                        return
                                    }
                                    avatarNode.isHidden = false
                                }
                            )
                        } else {
                            return nil
                        }
                    }
                )
                // `answered` is true only once the question below was answered.
                storyContainerScreen.donutgramGhostPromptAnswered = answered
                parentController?.push(storyContainerScreen)
            }
            // Nothing loaded, nothing to ask about: the viewer asks if a story
            // turns up.
            if state.slice == nil {
                open(false)
                return .complete()
            }
            return askDonutgramStoryGhostIfNeeded(context: context, parentController: parentController, open: open)
        }
        
        let disposable = avatarNode.pushLoadingStatus(signal: signal)
        if let sharedProgressDisposable {
            sharedProgressDisposable.set(disposable)
        }
    }
    
    static func openPeerStories(context: AccountContext, peerId: EnginePeer.Id, parentController: ViewController, avatarNode: AvatarNode?, sharedProgressDisposable: MetaDisposable? = nil) {
        return openPeerStoriesCustom(
            context: context,
            peerId: peerId,
            isHidden: false,
            singlePeer: true,
            parentController: parentController,
            transitionIn: { [weak avatarNode] in
                if let avatarNode {
                    let transitionIn = StoryContainerScreen.TransitionIn(
                        sourceView: avatarNode.view,
                        sourceRect: avatarNode.view.bounds,
                        sourceCornerRadius: avatarNode.view.bounds.width * 0.5,
                        sourceIsAvatar: false
                    )
                    avatarNode.isHidden = true
                    return transitionIn
                } else {
                    return nil
                }
            },
            transitionOut: { [weak avatarNode] _ in
                if let avatarNode {
                    let destinationView = avatarNode.view
                    return StoryContainerScreen.TransitionOut(
                        destinationView: destinationView,
                        transitionView: StoryContainerScreen.TransitionView(
                            makeView: { [weak destinationView] in
                                let parentView = UIView()
                                if let copyView = destinationView?.snapshotContentTree(unhide: true) {
                                    parentView.addSubview(copyView)
                                }
                                return parentView
                            },
                            updateView: { copyView, state, transition in
                                guard let view = copyView.subviews.first else {
                                    return
                                }
                                let size = state.sourceSize.interpolate(to: state.destinationSize, amount: state.progress)
                                transition.setPosition(view: view, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
                                transition.setScale(view: view, scale: size.width / state.destinationSize.width)
                            },
                            insertCloneTransitionView: nil
                        ),
                        destinationRect: destinationView.bounds,
                        destinationCornerRadius: destinationView.bounds.width * 0.5,
                        destinationIsAvatar: false,
                        completed: { [weak avatarNode] in
                            guard let avatarNode else {
                                return
                            }
                            avatarNode.isHidden = false
                        }
                    )
                } else {
                    return nil
                }
            },
            setFocusedItem: { _ in
            },
            setProgress: { [weak avatarNode] signal in
                guard let avatarNode else {
                    return
                }
                let disposable = avatarNode.pushLoadingStatus(signal: signal)
                if let sharedProgressDisposable {
                    sharedProgressDisposable.set(disposable)
                }
            }
        )
    }
    
    static func openPeerStoriesCustom(
        context: AccountContext,
        peerId: EnginePeer.Id,
        focusOnId: Int32? = nil,
        isHidden: Bool,
        initialOrder: [EnginePeer.Id] = [],
        singlePeer: Bool,
        parentController: ViewController,
        transitionIn: @escaping () -> StoryContainerScreen.TransitionIn?,
        transitionOut: @escaping (EnginePeer.Id) -> StoryContainerScreen.TransitionOut?,
        setFocusedItem: @escaping (Signal<EngineStoryId?, NoError>) -> Void,
        setProgress: @escaping (Signal<Never, NoError>) -> Void,
        completion: @escaping (StoryContainerScreen) -> Void = { _ in },
        skipGhostPrompt: Bool = false
    ) {
        let storyContent = StoryContentContextImpl(context: context, isHidden: isHidden, focusedPeerId: peerId, focusedStoryId: focusOnId, singlePeer: singlePeer, fixedOrder: initialOrder)
        let signal = storyContent.state
        |> take(1)
        |> mapToSignal { state -> Signal<StoryContentContextState, NoError> in
            if let slice = state.slice {
                #if DEBUG && false
                if "".isEmpty {
                    return .single(state)
                    |> delay(4.0, queue: .mainQueue())
                }
                #endif
                
                return waitUntilStoryMediaPreloaded(context: context, peerId: slice.effectivePeer.id, storyItem: slice.item.storyItem)
                |> timeout(4.0, queue: .mainQueue(), alternate: .complete())
                |> map { _ -> StoryContentContextState in
                }
                |> then(.single(state))
            } else {
                return .single(state)
            }
        }
        |> deliverOnMainQueue
        |> mapToSignal { [weak parentController] state -> Signal<Never, NoError> in
            if state.slice == nil {
                return .complete()
            }
            
            let open: (Bool) -> Void = { answered in
                let transitionIn: StoryContainerScreen.TransitionIn? = transitionIn()
                
                let storyContainerScreen = StoryContainerScreen(
                    context: context,
                    content: storyContent,
                    transitionIn: transitionIn,
                    transitionOut: { peerId, _ in
                        return transitionOut(peerId)
                    }
                )
                // `answered` is true only once the question below was answered.
                storyContainerScreen.donutgramGhostPromptAnswered = answered
                setFocusedItem(storyContainerScreen.focusedItem)
                parentController?.push(storyContainerScreen)
                completion(storyContainerScreen)
            }
            // Own stories open without the question; the viewer asks it once it
            // moves on to someone else's. «Смотреть анонимно» (`skipGhostPrompt`)
            // skips it too: the viewer lets receipts through while stealth mode
            // lasts and asks once it lapses.
            if skipGhostPrompt || peerId == context.account.peerId {
                open(false)
                return .complete()
            }
            return askDonutgramStoryGhostIfNeeded(context: context, parentController: parentController, open: open)
        }
        
        setProgress(signal)
    }
}
