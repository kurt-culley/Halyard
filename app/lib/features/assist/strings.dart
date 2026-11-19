import 'package:halyard_core/halyard_core.dart';

/// The tuning assistant's words, the original's where it had them.
abstract final class AssistStrings {
  static const title = 'Fuel tuning assistant';
  static const intro = 'Use live history, or load a CSV log, choose channels, then analyse.';
  static const detailIntro = 'Select a cell after analysis to inspect confidence, hits, and suggested change.';
  static const notOnline = 'Connect to an ECU to tune its VE table.';
  static const source = 'Samples';
  static const live = 'Live history';
  static const csv = 'CSV log';
  static const openCsv = 'Open CSV log…';
  static const csvType = 'CSV logs';
  static const veTable = 'VE table';
  static const targetTable = 'Target table';
  static const rpm = 'RPM channel';
  static const load = 'Load channel';
  static const measured = 'Measured AFR or lambda channel';
  static const mode = 'Measured as';
  static const afr = 'AFR';
  static const lambda = 'Lambda';
  static const stoich = 'Stoich AFR';
  static const minHits = 'Minimum hits';
  static const confidence = 'Confidence threshold';
  static const stability = 'Stability tolerance';
  static const maxChange = 'Maximum change';
  static const analyse = 'Analyse';
  static const applySelected = 'Apply selected';
  static const applyHigh = 'Apply high confidence';
  static const yes = 'Yes';
  static const no = 'No';
  static const legend = 'Green cells add fuel. Red cells remove fuel. Muted cells had weak or unstable evidence.';
  static const readOnly = 'Read only is on: turn it off on the connect page to apply.';
  static String unreadable(String why) => 'Could not load the CSV log.\n\n$why';
  static const noRows = 'The selected CSV does not contain any usable rows.';

  static String problem(TuningProblem p, {required bool csv}) => switch (p) {
    TuningProblem.veNotAMap => 'Select a 2D VE/fuel table first.',
    TuningProblem.noTarget => 'Select a target AFR table first.',
    TuningProblem.stoichOutOfRange => 'Stoich AFR must be a sensible value.',
    TuningProblem.noSamples =>
      csv
          ? 'No valid CSV rows are available for the selected columns.'
          : 'No playback/live history is available for the selected channels.',
  };
  static const chooseChannels = 'Select RPM, load, and lambda/AFR channels first.';

  static String done(int used, int ready, String? source) =>
      (ready > 0
          ? '$used samples used, $ready suggestions ready.'
          : '$used samples used, but no cells passed the confidence threshold.') +
      (source == null ? '' : ' Source: $source.');

  static String counts(int considered, int used, int rejected) =>
      'Samples considered: $considered   Used: $used   Rejected: $rejected';

  static String applyPrompt(int n) =>
      'Apply $n VE table change(s) and commit them through the existing table save workflow?';
  static String applied(int n) => 'Applied $n VE table change(s) and triggered the existing table save workflow.';

  static String note(SuggestionNote n) => switch (n) {
    SuggestionNote.needsMoreHits => 'Needs more repeated hits',
    SuggestionNote.lowConfidence => 'Low confidence / unstable samples',
    SuggestionNote.ready => 'Ready',
  };
}
