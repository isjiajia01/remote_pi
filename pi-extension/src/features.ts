/** Perch ships the phone companion by default. Full mode is explicit. */
export function fullFeatures(): boolean {
  return process.env.PERCH_FULL_FEATURES === "1";
}
export function extraCommand(command: string): boolean {
  return /^(peers|create|remove|daemons?|cron|install|uninstall)(\s|$)/.test(command);
}
