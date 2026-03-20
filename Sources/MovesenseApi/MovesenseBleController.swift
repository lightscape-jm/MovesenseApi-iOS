//
//  MovesenseBleController.swift
//  MovesenseApi
//
//  Copyright © 2018 Suunto. All rights reserved.
//

import CoreBluetooth

protocol MovesenseBleControllerDelegate: AnyObject {

    func deviceFound(uuid: UUID, localName: String,
                     serialNumber: String, rssi: Int)
}

protocol MovesenseBleController: AnyObject {

    var delegate: MovesenseBleControllerDelegate? { get set }

    var mdsCentralManager: CBCentralManager? { get }

    func startScan()
    func stopScan()
}

final class MovesenseBleControllerConcrete: NSObject, MovesenseBleController {

    weak var delegate: MovesenseBleControllerDelegate?

    // Keep this one here to use the same queue with our own central
    private(set) var mdsCentralManager: CBCentralManager?

    private let bleQueue: DispatchQueue

    private var centralManager: CBCentralManager?

    // Track peripherals already reported via retrieveConnectedPeripherals
    // to avoid repeated discovery on every startScan call
    private var reportedConnectedPeripherals: Set<UUID> = []

    override init() {
        self.bleQueue = DispatchQueue(label: "com.movesense.ble")
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bleQueue, options: nil)
        mdsCentralManager = CBCentralManager(delegate: self, queue: bleQueue, options: nil)
    }

    func startScan() {
        guard let centralManager = centralManager else {
            NSLog("MovesenseBleController::stopScan integrity error.")
            return
        }

        if centralManager.state != .poweredOn {
            NSLog("MovesenseBleController::startScan Bluetooth not on.")
            return
        }

        // Check for peripherals already connected at the system level.
        // iOS may auto-reconnect BLE devices, preventing them from advertising.
        // Disconnect them so the sensor resumes advertising and MDS can connect properly.
        for serviceUUID in Movesense.MOVESENSE_SERVICES {
            let connected = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
            for peripheral in connected {
                guard !reportedConnectedPeripherals.contains(peripheral.identifier) else {
                    continue
                }
                if let localName = peripheral.name, isMovesense(localName) {
                    NSLog("MovesenseBleController::startScan releasing system-connected peripheral: \(localName) uuid=\(peripheral.identifier)")
                    reportedConnectedPeripherals.insert(peripheral.identifier)
                    centralManager.cancelPeripheralConnection(peripheral)
                }
            }
        }

        centralManager.scanForPeripherals(withServices: Movesense.MOVESENSE_SERVICES,
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        guard let centralManager = centralManager else {
            NSLog("MovesenseBleController::stopScan integrity error.")
            return
        }

        if centralManager.state != .poweredOn {
            NSLog("MovesenseBleController::stopScan Bluetooth not on.")
            return
        }

        if centralManager.isScanning == false {
            return
        }

        reportedConnectedPeripherals.removeAll()
        centralManager.stopScan()
    }

    private func isMovesense(_ localName: String) -> Bool {
        let index = localName.firstIndex(of: " ") ?? localName.endIndex
        return localName[localName.startIndex..<index] == "Movesense"
    }

    private func parseSerial(_ localName: String) -> String? {
        guard isMovesense(localName),
              let idx = localName.range(of: " ", options: .backwards)?.lowerBound else {
            return nil
        }

        return String(localName[localName.index(after: idx)...])
    }
}

extension MovesenseBleControllerConcrete: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case CBManagerState.poweredOff:
            NSLog("centralManagerDidUpdateState: poweredOff")
        case CBManagerState.poweredOn:
            NSLog("centralManagerDidUpdateState: poweredOn")
        default:
            NSLog("centralManagerDidUpdateState: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let localName = peripheral.name,
              let serialNumber = parseSerial(localName) else {
            return
        }

        delegate?.deviceFound(uuid: peripheral.identifier, localName: localName,
                              serialNumber: serialNumber, rssi: RSSI.intValue)
    }
}
