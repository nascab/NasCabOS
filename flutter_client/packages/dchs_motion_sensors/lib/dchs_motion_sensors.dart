import 'dart:async';

final MotionSensors motionSensors = MotionSensors();

class AccelerometerEvent {
  AccelerometerEvent(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class MagnetometerEvent {
  MagnetometerEvent(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class GyroscopeEvent {
  GyroscopeEvent(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class UserAccelerometerEvent {
  UserAccelerometerEvent(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class OrientationEvent {
  OrientationEvent(this.yaw, this.pitch, this.roll);

  final double yaw;
  final double pitch;
  final double roll;
}

class AbsoluteOrientationEvent {
  AbsoluteOrientationEvent(this.yaw, this.pitch, this.roll);

  final double yaw;
  final double pitch;
  final double roll;
}

class ScreenOrientationEvent {
  ScreenOrientationEvent(this.angle);

  final double? angle;
}

class MotionSensors {
  static const int typeAccelerometer = 1;
  static const int typeMagneticField = 2;
  static const int typeGyroscope = 4;
  static const int typeUserAccelerometer = 10;
  static const int typeOrientation = 15;
  static const int typeAbsoluteOrientation = 11;

  Future<bool> isSensorAvailable(int sensorType) async => false;

  Future<bool> isAccelerometerAvailable() => isSensorAvailable(typeAccelerometer);

  Future<bool> isMagnetometerAvailable() => isSensorAvailable(typeMagneticField);

  Future<bool> isGyroscopeAvailable() => isSensorAvailable(typeGyroscope);

  Future<bool> isUserAccelerationAvailable() =>
      isSensorAvailable(typeUserAccelerometer);

  Future<bool> isOrientationAvailable() => isSensorAvailable(typeOrientation);

  Future<bool> isAbsoluteOrientationAvailable() =>
      isSensorAvailable(typeAbsoluteOrientation);

  Future<void> setSensorUpdateInterval(int sensorType, int interval) async {}

  set accelerometerUpdateInterval(int interval) {}

  set magnetometerUpdateInterval(int interval) {}

  set gyroscopeUpdateInterval(int interval) {}

  set userAccelerometerUpdateInterval(int interval) {}

  set orientationUpdateInterval(int interval) {}

  set absoluteOrientationUpdateInterval(int interval) {}

  Stream<AccelerometerEvent> get accelerometer => Stream.empty();

  Stream<GyroscopeEvent> get gyroscope => Stream.empty();

  Stream<UserAccelerometerEvent> get userAccelerometer => Stream.empty();

  Stream<MagnetometerEvent> get magnetometer => Stream.empty();

  Stream<OrientationEvent> get orientation => Stream.empty();

  Stream<AbsoluteOrientationEvent> get absoluteOrientation => Stream.empty();

  Stream<ScreenOrientationEvent> get screenOrientation => Stream.empty();
}
