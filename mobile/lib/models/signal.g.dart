// Hive TypeAdapter untuk Signal (ditulis manual, setara output hive_generator).

part of 'signal.dart';

class SignalAdapter extends TypeAdapter<Signal> {
  @override
  final int typeId = 2;

  @override
  Signal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Signal(
      symbol: fields[0] as String,
      direction: fields[1] as String,
      entry: fields[2] as double,
      stopLoss: fields[3] as double,
      takeProfit: fields[4] as double,
      confidence: fields[5] as double,
      riskReward: fields[6] as double,
      triggeredStrategies:
          (fields[7] as List).map((e) => e as String).toList(),
      timestamp: fields[8] as int,
      note: fields[9] as String? ?? '',
      outcome: fields[10] as String? ?? SignalOutcome.pending,
      resolvedAt: fields[11] as int? ?? 0,
      profitLoss: (fields[12] as num?)?.toDouble() ?? 0,
      // Rekaman LAMA tanpa field 13 → skema versi 1 (backward-compatible).
      schemaVersion: fields[13] as int? ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, Signal obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.symbol)
      ..writeByte(1)
      ..write(obj.direction)
      ..writeByte(2)
      ..write(obj.entry)
      ..writeByte(3)
      ..write(obj.stopLoss)
      ..writeByte(4)
      ..write(obj.takeProfit)
      ..writeByte(5)
      ..write(obj.confidence)
      ..writeByte(6)
      ..write(obj.riskReward)
      ..writeByte(7)
      ..write(obj.triggeredStrategies)
      ..writeByte(8)
      ..write(obj.timestamp)
      ..writeByte(9)
      ..write(obj.note)
      ..writeByte(10)
      ..write(obj.outcome)
      ..writeByte(11)
      ..write(obj.resolvedAt)
      ..writeByte(12)
      ..write(obj.profitLoss)
      ..writeByte(13)
      ..write(obj.schemaVersion);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
