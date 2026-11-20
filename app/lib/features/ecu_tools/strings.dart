/// The ECU tools' words: the original's, without its vendor names.
abstract final class EcuToolsStrings {
  static const notOnline = 'Operation can only be performed while the ECU is connected.';
  static const readOnly = 'Read only is on: turn it off on the connect page to change the ECU.';

  static const dateTitle = 'Date & Time';
  static const ecuTime = 'ECU Date and Time:';
  static const newTime = 'New Date and Time:';
  static const noClock = 'This definition has no clock channels.';
  static const pickDate = 'Date';
  static const pickTime = 'Time';
  static const saveTime = 'Save To ECU';
  static const timeSaved = 'Sent. The ECU keeps no seconds from this.';

  static const pwTitle = 'Password Protection';
  static const pwState = 'ECU State:';
  static const contact = 'Tuner Contact Details:';
  static const password = 'Password:';
  static const again = 'Re-enter password:';
  static const lock = 'Lock';
  static const unlock = 'Unlock';
  static const permanent = 'Permanent Unlock:';
  static const unlockedPermanent = 'Unlocked - Permanent.';
  static const unlockedTemporary = 'Unlocked - Temporarily.';
  static const locked = "Password-protected. Map can't be seen or edited.";
  static const tooLong = 'Please enter a password no longer than 16 characters.';
  static const mismatch = "The two passwords don't match.";
  static const refused = 'The ECU refused the password.';

  static const resetTitle = 'Factory Reset ECU';
  static const resetPrompt = 'Please enter ERASE to delete the calibration on your ECU and return it to factory state.';
  static const resetWarning =
      'WARNING: This cannot be undone! Your ECU will now reset, this should take approximately 20 seconds and you will '
      'lose connection to the ECU.';
  static const resetFirmware = 'Only on firmware versions newer than 3.9.1';
  static const resetButton = 'Factory reset…';
  static const ok = 'OK';
  static const cancel = 'Cancel';
  static const wrongText = "Please make sure that you're entering the correct text.";
  static const resetDone = 'ECU successfully reset to factory settings. Please restart the app.';
  static const resetFailed = "Factory reset couldn't be completed.";
  static const noAnswer = 'The ECU did not answer.';
}
