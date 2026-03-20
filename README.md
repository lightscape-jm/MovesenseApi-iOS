# MovesenseApi-iOS (Fork)

Event-based Swift API for communicating with [Movesense](https://www.movesense.com) sensors via Bluetooth LE.

This is a fork of [mikkojeronen/MovesenseApi-iOS](https://github.com/mikkojeronen/MovesenseApi-iOS), modified for use in the [Movesense Dive Telemetry](https://github.com/lightscape-jm/Movesense-Dive-Telemetry) project — a scuba diving sensor data recording and analysis system.

## Changes from Upstream

### New Sensor Resource Types
- **Magnetometer** (`Meas/Magn`) — subscribe/unsubscribe support for magnetometer data streams
- **Magnetometer Info** (`Meas/Magn/Info`) — query available sample rates
- **IMU6** (`Meas/IMU6`) — 6-axis inertial measurement unit (accelerometer + gyroscope combined)
- **System Time** (`Time`) — get/set device time for timestamp synchronization
- **UART Settings** (`System/Settings/UartOn`) — get/put UART state

### New Data Types
- `MovesenseMagn` — magnetometer data with timestamp and 3D vectors
- `MovesenseMagnInfo` — magnetometer capability info (sample rates)
- `MovesenseIMU` — IMU6 data with timestamp, accelerometer and gyroscope vectors
- `MovesenseSystemTime` — device system time value

### New Events
- `MovesenseEvent.magn` — magnetometer subscription events
- `MovesenseEvent.imu` — IMU subscription events

### New Responses
- `MovesenseResponse.magnInfo` — magnetometer info response
- `MovesenseResponse.systemTime` — system time response

### Other Changes
- Added public initializers to `MovesenseAcc`, `MovesenseEcg`, `MovesenseGyro`, `MovesenseMagn`, `MovesenseIMU`, and `MovesenseVector3D` for use outside the module
- Added new operations: `MovesenseOperationSystemTime`, `MovesenseOperationSettingsUartOn`
- MDS dependency now points to [lightscape-jm/MovesenseMds-iOS](https://github.com/lightscape-jm/MovesenseMds-iOS)

## Dependencies

- [MovesenseMds-iOS](https://github.com/lightscape-jm/MovesenseMds-iOS) (via Swift Package Manager)

## Integration

Add as a Swift Package dependency:
```
https://github.com/lightscape-jm/MovesenseApi-iOS.git
```
Branch: `main`
