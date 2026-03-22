//
//  MovesenseController.swift
//  MovesenseApi
//
//  Copyright © 2018 Suunto. All rights reserved.
//

import Foundation
import MovesenseMds

protocol MovesenseControllerDelegate: AnyObject {

    func deviceDiscovered(_ device: MovesenseDeviceConcrete)

    func deviceConnecting(_ serialNumber: MovesenseSerialNumber)
    func deviceConnected(_ deviceInfo: MovesenseDeviceInfo,
                         _ connection: MovesenseConnection)
    func deviceDisconnected(_ serialNumber: MovesenseSerialNumber)

    func onControllerError(_ error: Error)
}

class MovesenseController: NSObject {

    weak var delegate: MovesenseControllerDelegate?

    private let jsonDecoder: JSONDecoder = JSONDecoder()
    private let bleController: MovesenseBleController
    private let mdsWrapper: MDSWrapper
    private var mdsVersionNumber: String?

    private weak var movesenseModel: MovesenseModel?

    init(model: MovesenseModel,
         bleController: MovesenseBleController) {

        self.movesenseModel = model
        self.bleController = bleController

        // Initialize MDSWrapper with a separate CBCentralManager created in BleController to prevent MDS from doing
        // state restoration for it during initialization, which pretty much messes up the peripheral connection states
        // for good.
        self.mdsWrapper = MDSWrapper(Bundle.main, centralManager: bleController.mdsCentralManager, deviceUUIDs: nil)

        super.init()

        mdsWrapper.delegate = self
        bleController.delegate = self
        subscribeToDeviceConnections()
        getMDSVersion()
    }

    func mdsVersion() -> String? {
        return mdsVersionNumber
    }

    func shutdown() {
        mdsWrapper.deactivate()
    }

    /// Start looking for Movesense devices
    func startScan() {
        bleController.startScan()
    }

    /// Stop looking for Movesense devices
    func stopScan() {
        bleController.stopScan()
    }

    /// Establish a connection to the specific Movesense device
    func connectDevice(_ serial: MovesenseSerialNumber) {
        NSLog("MovesenseController::connectDevice serial=\(serial)")

        guard let device = movesenseModel?[serial] else {
            NSLog("MovesenseController::connectDevice ERROR: No such device in model for serial=\(serial)")
            delegate?.onControllerError(MovesenseError.controllerError("No such device."))
            return
        }

        NSLog("MovesenseController::connectDevice found device uuid=\(device.uuid) state=\(device.deviceState) isConnected=\(device.isConnected)")

        guard device.isConnected == false else {
            NSLog("MovesenseController::connectDevice ERROR: Already connected")
            delegate?.onControllerError(MovesenseError.controllerError("Already connected."))
            return
        }

        delegate?.deviceConnecting(serial)

        NSLog("MovesenseController::connectDevice calling mdsWrapper.connectPeripheral uuid=\(device.uuid)")
        mdsWrapper.connectPeripheral(with: device.uuid)
    }

    /// Disconnect specific Movesense device
    func disconnectDevice(_ serial: MovesenseSerialNumber) {
        guard let device = movesenseModel?[serial] else {
            delegate?.onControllerError(MovesenseError.controllerError("No such device."))
            return
        }

        delegate?.deviceDisconnected(device.serialNumber)

        mdsWrapper.disconnectPeripheral(with: device.uuid)
    }

    private func getMDSVersion() {
        mdsWrapper.doGet(MovesenseConstants.mdsVersion,
                         contract: [:],
                         completion: {[weak self] (event) in
            guard let this = self else {
                NSLog("MovesenseController integrity error.")
                // TODO: Propagate error
                return
            }

            // TODO: All decoding needs to be done asynchronously since it may take arbitrary time.
            // TODO: Do it here temporarily.
            guard let decodedEvent = try? this.jsonDecoder.decode(MovesenseResponseContainer<String>.self,
                                                                  from: event.bodyData) else {
                let error = MovesenseError.decodingError("MovesenseController: unable to decode MDS version event.")
                NSLog(error.localizedDescription)
                this.delegate?.onControllerError(error)
                return
            }

            this.mdsVersionNumber = decodedEvent.content
        })
    }

    private func subscribeToDeviceConnections() {
        mdsWrapper.doSubscribe(
            MovesenseConstants.mdsConnectedDevices,
            contract: [:],
            response: { (response) in
                NSLog("MovesenseController::subscribeToDeviceConnections response statusCode=\(response.statusCode) method=\(response.method.rawValue)")
                guard response.statusCode == MovesenseResponseCode.ok.rawValue,
                      response.method == MDSResponseMethod.SUBSCRIBE else {
                    NSLog("MovesenseController invalid response to connection subscription.")
                    // TODO: Propagate error
                    return
                }
            },
            onEvent: { [weak self] (event) in
                NSLog("MovesenseController::subscribeToDeviceConnections onEvent bodyData=\(String(data: event.bodyData, encoding: .utf8) ?? "nil")")

                guard let this = self,
                      let delegate = this.delegate else {
                    NSLog("MovesenseController integrity error.")
                    // TODO: Propagate error
                    return
                }

                // TODO: All decoding needs to be done asynchronously since it may take arbitrary time.
                // TODO: Do it here temporarily.
                guard let decodedEvent = try? this.jsonDecoder.decode(MovesenseDeviceEvent.self,
                                                                      from: event.bodyData) else {
                    let bodyStr = String(data: event.bodyData, encoding: .utf8) ?? "nil"
                    let error = MovesenseError.decodingError("MovesenseController: unable to decode device connection response. Body: \(bodyStr)")
                    NSLog(error.localizedDescription)
                    this.delegate?.onControllerError(error)
                    return
                }

                NSLog("MovesenseController::subscribeToDeviceConnections decoded eventMethod=\(decodedEvent.eventMethod) serial=\(decodedEvent.eventBody.serialNumber)")

                switch decodedEvent.eventMethod {
                case .post:
                    guard let deviceInfo = decodedEvent.eventBody.deviceInfo,
                          let connectionInfo = decodedEvent.eventBody.connectionInfo else {
                        NSLog("MovesenseController::subscribeToDeviceConnections ERROR: post event missing deviceInfo or connectionInfo")
                        return
                    }

                    NSLog("MovesenseController::subscribeToDeviceConnections CONNECTED serial=\(deviceInfo.serialNumber)")
                    this.mdsWrapper.disableAutoReconnectForDevice(withSerial: deviceInfo.serialNumber)
                    let connection = MovesenseConnection(mdsWrapper: this.mdsWrapper,
                                                         jsonDecoder: this.jsonDecoder,
                                                         connectionInfo: connectionInfo)
                    delegate.deviceConnected(deviceInfo, connection)
                case .del:
                    NSLog("MovesenseController::subscribeToDeviceConnections DISCONNECTED serial=\(decodedEvent.eventBody.serialNumber)")
                    delegate.deviceDisconnected(decodedEvent.eventBody.serialNumber)
                default:
                    NSLog("MovesenseController::subscribeToDeviceConnections unknown event method.")
                    this.delegate?.onControllerError(MovesenseError.controllerError("Unknown event method"))
                }
            })
    }

    // MARK: - Raw MDS Request Passthrough

    /// Perform a raw MDS GET request without typed resource handling.
    /// Used for DataLogger, Logbook, and other endpoints without typed API support.
    func rawGet(_ uri: String, contract: [String: Any], completion: @escaping (_ statusCode: Int, _ body: Data) -> Void) {
        mdsWrapper.doGet(uri, contract: contract) { response in
            completion(Int(response.statusCode), response.bodyData)
        }
    }

    func rawPut(_ uri: String, contract: [String: Any], completion: @escaping (_ statusCode: Int, _ body: Data) -> Void) {
        mdsWrapper.doPut(uri, contract: contract) { response in
            completion(Int(response.statusCode), response.bodyData)
        }
    }

    func rawPost(_ uri: String, contract: [String: Any], completion: @escaping (_ statusCode: Int, _ body: Data) -> Void) {
        mdsWrapper.doPost(uri, contract: contract) { response in
            completion(Int(response.statusCode), response.bodyData)
        }
    }

    func rawDelete(_ uri: String, contract: [String: Any], completion: @escaping (_ statusCode: Int, _ body: Data) -> Void) {
        mdsWrapper.doDelete(uri, contract: contract) { response in
            completion(Int(response.statusCode), response.bodyData)
        }
    }
}

extension MovesenseController: MovesenseBleControllerDelegate {

    func deviceFound(uuid: UUID, localName: String, serialNumber: String, rssi: Int) {
        let device = MovesenseDeviceConcrete(uuid: uuid, localName: localName,
                                      serialNumber: serialNumber, rssi: rssi)
        delegate?.deviceDiscovered(device)
    }
}

extension MovesenseController: MDSConnectivityServiceDelegate {

    func didFailToConnectWithError(_ error: Error?) {
        // NOTE: The error is a null pointer and accessing it will cause a crash
        NSLog("MovesenseController::didFailToConnectWithError - MDS connection failed")
        delegate?.onControllerError(MovesenseError.controllerError("Did fail to connect."))
    }
}
