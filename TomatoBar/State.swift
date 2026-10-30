import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, startRest, timerFired, skipRest, screenLocked
}

enum TBStateMachineStates: StateType {
    case idle, work, rest
}
