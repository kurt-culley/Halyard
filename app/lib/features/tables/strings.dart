abstract final class TablesStrings {
  static const notOnline = 'Connect to an ECU to see its tables.';
  static const choose = 'Choose a table.';
  static const other = 'Other';
  static const disabled = 'Disabled';
  static const readOnly = 'Read only: editing arrives with the write gate.';
  static String table(int id) => 'Table $id';
  static String axes(String? x, String? y) => [if (x != null) 'Across: $x', if (y != null) 'Down: $y'].join('   ');
}
