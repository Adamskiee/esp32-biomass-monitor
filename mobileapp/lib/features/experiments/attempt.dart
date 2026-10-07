enum AttemptScenario { withoutFiltration, withFiltration }

enum AttemptStatus { active, completed, interrupted }

extension AttemptScenarioStorage on AttemptScenario {
  String get storageValue => this == AttemptScenario.withoutFiltration
      ? 'without_filtration'
      : 'with_filtration';
  String get labelPrefix => this == AttemptScenario.withoutFiltration
      ? 'Without filtration'
      : 'With filtration';
  static AttemptScenario parse(String value) => switch (value) {
    'without_filtration' => AttemptScenario.withoutFiltration,
    'with_filtration' => AttemptScenario.withFiltration,
    _ => throw FormatException('Unknown attempt scenario: $value'),
  };
}

extension AttemptStatusStorage on AttemptStatus {
  String get storageValue => name;
  static AttemptStatus parse(String value) => switch (value) {
    'active' => AttemptStatus.active,
    'completed' => AttemptStatus.completed,
    'interrupted' => AttemptStatus.interrupted,
    _ => throw FormatException('Unknown attempt status: $value'),
  };
}

class Attempt {
  const Attempt({
    required this.id,
    required this.scenario,
    required this.sequenceNumber,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.sampleCount,
  });
  final int id;
  final AttemptScenario scenario;
  final int sequenceNumber;
  final DateTime startedAt;
  final DateTime? endedAt;
  final AttemptStatus status;
  final int sampleCount;
  String get label => '${scenario.labelPrefix} #$sequenceNumber';
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);
}
