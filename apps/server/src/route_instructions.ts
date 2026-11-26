import type { ProviderPayload } from './types.ts';

/** How far past a motorway exit we look for the road the ramp delivers you to.
 * Ramps are usually one or two unnamed steps; anything longer is a different
 * maneuver and keeps the engine's own sentence. */
const MAX_RAMP_STEPS = 3;
const MAX_RAMP_METRES = 3000;

const TURN_TYPES = new Set(['turn', 'end of road', 'fork', 'continue', 'new name', 'merge']);

function roadLabel(step: ProviderPayload): string {
  const name = typeof step.name === 'string' ? step.name.trim() : '';
  const ref = typeof step.ref === 'string' ? step.ref.trim() : '';
  // State highway numbers are on the green signs; local route numbers are not.
  if (name && /^SH\s?\d/i.test(ref) && !name.includes(ref)) return `${ref}/${name}`;
  return name;
}

function exitSentence(exit: string, road: string, chinese: boolean): string {
  if (chinese) return exit ? `走${exit}号出口，前往${road}。` : `从出口驶出，前往${road}。`;
  return exit ? `Take exit ${exit} towards ${road}.` : `Take the exit towards ${road}.`;
}

function followSentence(step: ProviderPayload, road: string, chinese: boolean): string {
  const type = String(step.maneuver?.type || '');
  const modifier = String(step.maneuver?.modifier || '');
  const left = modifier.includes('left');
  const right = modifier.includes('right');
  if (type === 'fork' || type === 'merge' || modifier.startsWith('slight')) {
    if (left || right) {
      if (chinese) return `保持${left ? '左' : '右'}侧，进入${road}。`;
      return `Keep ${left ? 'left' : 'right'} onto ${road}.`;
    }
  } else if (left || right) {
    const sharp = modifier.startsWith('sharp');
    if (chinese) return `${sharp ? '向' : ''}${left ? '左' : '右'}${sharp ? '急转' : '转'}进入${road}。`;
    return `Turn ${sharp ? 'sharp ' : ''}${left ? 'left' : 'right'} onto ${road}.`;
  }
  return chinese ? `继续进入${road}。` : `Continue onto ${road}.`;
}

/**
 * Motorway exits read like the road you end up on, the way the green sign and
 * Google Maps put it: "Take exit 414 towards Constellation Drive", then
 * "Turn right onto Constellation Drive". Valhalla instead lists every OSM
 * `destination` on the ramp ("onto SH 18/Upper Harbour Highway towards
 * Greenhithe/Waitakere/Mairangi Bay/AUT Millennium") and the following turn
 * names only those towns, never the street.
 *
 * Returns one instruction per step; steps that are not an exit or the turn
 * that ends one keep the engine's text unchanged.
 */
export function conciseExitInstructions(steps: ProviderPayload[], language?: string): string[] {
  const chinese = language === 'zh';
  const instructions = steps.map(step => String(step.maneuver?.instruction || ''));
  for (let i = 0; i < steps.length; i++) {
    if (steps[i].maneuver?.type !== 'off ramp') continue;
    let metres = Number(steps[i].distance || 0);
    for (let j = i + 1; j < steps.length && j <= i + MAX_RAMP_STEPS; j++) {
      const next = steps[j];
      const type = String(next.maneuver?.type || '');
      if (type === 'arrive' || type === 'off ramp') break;
      const road = roadLabel(next);
      if (!road) {
        // Still on the unnamed ramp: a fork or merge partway along it.
        metres += Number(next.distance || 0);
        if (metres > MAX_RAMP_METRES) break;
        continue;
      }
      const exit = typeof steps[i].exits === 'string' ? steps[i].exits.split(';')[0].trim() : '';
      instructions[i] = exitSentence(exit, road, chinese);
      // The turn off the ramp onto that road names the road rather than towns.
      const name = String(next.name || '').trim();
      if (TURN_TYPES.has(type) && !instructions[j].includes(name)) {
        instructions[j] = followSentence(next, road, chinese);
      }
      break;
    }
  }
  return instructions;
}
