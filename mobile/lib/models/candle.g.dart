// Hive TypeAdapter untuk Candle.
//
// File ini biasanya dihasilkan oleh `build_runner` (hive_generator). Karena
// adapternya sederhana dan agar proyek dapat langsung dibangun tanpa langkah
// codegen, adapter ditulis manual di sini dengan output yang setara.

part of 'candle.dart';

class CandleAdapter extends TypeAdapter<Candle> {
  @override
  final int typeId = 1;

  @override
  Candle read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Candle(
      openTime: fields[0] as int,
      open: fields[1] as double,
      high: fields[2] as double,
      low: fields[3] as double,
      close: fields[4] as double,
      volume: fields[5] as double,
      closeTime: fields[6] as int,
      isClosed: fields[7] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, Candle obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.openTime)
      ..writeByte(1)
      ..write(obj.open)
      ..writeByte(2)
      ..write(obj.high)
      ..writeByte(3)
      ..write(obj.low)
      ..writeByte(4)
      ..write(obj.close)
      ..writeByte(5)
      ..write(obj.volume)
      ..writeByte(6)
      ..write(obj.closeTime)
      ..writeByte(7)
      ..write(obj.isClosed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CandleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
