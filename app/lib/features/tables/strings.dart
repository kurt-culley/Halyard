abstract final class TablesStrings {
  static const notOnline = 'Connect to an ECU to see its tables.';
  static const choose = 'Choose a table.';
  static const other = 'Other';
  static const disabled = 'Disabled';
  static const readOnly = 'Read only: turn off read only on the connect page to edit.';
  static const editHint = 'Value or formula';
  static const editHelp = 'Choose a cell, then type a value or a formula (+20, *1.06, -5%, =35) and press Enter.';
  static const store = 'Store to flash';
  static const stored = 'Stored.';
  static const notNumber = 'That is not a number or a formula.';
  static String failed(String what) => 'The ECU did not accept the change ($what).';
  static String table(int id) => 'Table $id';
  static String axes(String? x, String? y) => [if (x != null) 'Across: $x', if (y != null) 'Down: $y'].join('   ');
}
