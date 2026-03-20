//
//  Observer.swift
//  MovesenseApi
//
//  Copyright © 2018 Suunto. All rights reserved.
//

import Foundation

public protocol ObserverEvent {}

public protocol Observer: AnyObject {

    func handleEvent(_ event: ObserverEvent)
}

extension Observer {

    func handleEvent(_ event: ObserverEvent) {
        assertionFailure("Observer::handleEvent not implemented.")
    }
}

public struct Observation {

    weak var observer: Observer?
}

public protocol Observable: AnyObject {

    var observations: [Observation] { get set }
    var observationQueue: DispatchQueue { get }

    func addObserver(_ observer: Observer)
    func removeObserver(_ observer: Observer)
    func notifyObservers(_ event: ObserverEvent)
}

// Serial queue shared by all Observable instances for thread-safe observer management
private let observerSyncQueue = DispatchQueue(label: "com.movesense.observer.sync")

public extension Observable {

    func addObserver(_ observer: Observer) {
        observerSyncQueue.sync {
            guard (observations.contains { $0.observer === observer } == false) else {
                NSLog("Observable::addObserver: Observer added already.")
                return
            }

            observations.append(Observation(observer: observer))
        }
    }

    func removeObserver(_ observer: Observer) {
        observerSyncQueue.sync {
            observations = observations.filter {
                ($0.observer != nil) && ($0.observer !== observer)
            }
        }
    }

    func notifyObservers(_ event: ObserverEvent) {
        let currentObservations = observerSyncQueue.sync { observations }
        observationQueue.async {
            currentObservations.compactMap { $0.observer }.forEach { $0.handleEvent(event) }
        }
    }
}
