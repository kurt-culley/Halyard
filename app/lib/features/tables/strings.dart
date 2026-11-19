abstract final class TablesStrings {
  static const notOnline = 'Connect to an ECU to see its tables.';
  static const choose = 'Choose a table.';
  static const search = 'Find a table';
  static const other = 'Other';
  static const disabled = 'Disabled';
  static const readOnly = 'Read only: turn off read only on the connect page to edit.';
  static const store = 'Store to flash';
  static const stored = 'Stored.';
  static const unstored = 'Not stored to flash yet';
  static const matchesFlash = 'Matches flash';
  static const notNumber = 'That is not a number.';
  static const notFormula = 'That is not a formula.';
  static String failed(String what) => 'The ECU did not accept the change ($what).';
  static String table(int id) => 'Table $id';

  // The original's wording for its two boxes.
  static const formulaTitle = 'Please enter formula for selected cells';
  static const formulaText =
      'Input math operation (see examples):\n'
      '+20 - Adds 20\n'
      '-10 - Subtracts 10 from cells\n'
      '*1.6  - Multiplies selected cells by 1.6\n'
      '/3 - Divide by 3.\n'
      '+10% - Adds 10%\n'
      '-15% - Removes 15% from all selected cells\n'
      '=35 - Replaces selected values with 35';
  static const setValueTitle = 'Please enter new value for selected cells';
  static const setValue = 'Set value';
  static const ok = 'OK';
  static const cancel = 'Cancel';

  // Toolbar and menu.
  static const follow = 'Follow (F)';
  static const smooth = 'Smooth (E)';
  static const radius = 'Smooth radius';
  static const up = 'Up by the increment (W)';
  static const down = 'Down by the increment (Q)';
  static const upFine = 'Up by a tenth (S)';
  static const downFine = 'Down by a tenth (A)';
  static const set = 'Set value (Enter)';
  static const formula = 'Formula (+)';
  static const tuned = 'Mark tuned (T)';
  static const copy = 'Copy (Ctrl+C)';
  static const paste = 'Paste (Ctrl+V)';
  static const graph = 'Graph';
  static const view3d = '3D';
  static const interpolateOutput = 'Interpolate Output';
  static const horizontally = 'Horizontally';
  static const vertically = 'Vertically';
  static String interpolate(String? axis) => 'Interpolate ${axis ?? ''}';
  static const setStart = 'Set interpolation start';
  static const setEnd = 'Set interpolation end';
  static String interpolateMarked(String? axis) => 'Interpolate marked ${axis ?? ''}';
  static const clearMarks = 'Clear axis interpolation marks';
  static String copyAxis(String? axis) => 'Copy ${axis ?? ''} to clipboard';
  static String pasteAxis(String? axis) => 'Paste to ${axis ?? ''} from clipboard';
  static const hint =
      'W/Q step by the increment, S/A by a tenth, Enter sets a value, + applies a formula, E smooths, '
      'T marks tuned. Shift or drag selects a block, Ctrl adds cells, right-click for more.';
  static String values(String? out, String? across, String? down) => [
    if (out != null) 'Values: $out',
    if (across != null) 'across: $across',
    if (down != null) 'down: $down',
  ].join(',  ');
}
