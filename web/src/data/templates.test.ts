import { describe, expect, it } from 'vitest';
import { BUILTIN_TEMPLATES } from './templates';
import type { PoseCategory } from '../types';

const expectedCategories: Record<PoseCategory, string[]> = {
  standing: [
    'crossed-arms-standing', 'back-facing-arms-open', 'side-lean-arms-open',
    'wall-lean-body-side-one-hand-pocket', 'standing-look-back-one-hand-pocket',
    'one-hand-in-pocket', 'standing-one-arm-up', 'both-arms-raised',
    'natural-stand-hands-front', 'one-leg-back-lift', 'one-leg-forward-toe-up',
    'walking-side-profile', 'side-stand-arms-down', 'forward-lean-hands-low',
    'arms-crossed-one-leg-lifted', 'arms-open-look-side',
    'railing-standing-one-hand-shade-eyes', 'wall-touch-one-hand-one-foot-forward',
    'wall-lean-body-side-hands-low',
  ],
  half: [
    'hand-near-hair-or-forehead', 'hand-in-hair-standing', 'both-hands-near-face',
    'one-hand-near-ear-other-low', 'one-hand-on-shoulder-other-low', 'standing-salute',
    'standing-both-hands-near-head', 'standing-both-hands-waist-look-side',
    'side-look-back-hand-behind-head', 'two-hands-front-asymmetric',
    'back-facing-both-hands-in-hair', 'mirror-standing-one-hand-phone',
  ],
  seated: [
    'seated-both-hands-cup-face', 'seated-hand-near-forehead',
    'seated-knees-open-hands-low', 'seated-one-hand-in-hair',
    'seated-one-hand-support-cheek', 'seated-one-hand-support-chin',
    'floor-seated-cross-legged-hold-prop',
    'floor-seated-knees-raised-one-hand-near-face',
    'low-seated-one-leg-extended-selfie',
    'steps-seated-crossed-legs-both-hands-behind-head',
    'steps-seated-side-one-hand-near-ear',
  ],
  crouching: [
    'crouch-knees-together-both-hands-cup-face',
    'crouch-knees-together-hands-low',
    'crouch-knees-together-one-hand-cheek', 'crouch-one-hand-in-hair',
    'crouch-one-knee-up-hand-near-face', 'low-crouch', 'one-knee-kneel',
    'low-kneel-arms-extended-look-side',
  ],
};

describe('reviewed pose categories', () => {
  it('keeps all 50 built-in poses in the audited category contract', () => {
    expect(BUILTIN_TEMPLATES).toHaveLength(50);
    for (const [category, expectedIds] of Object.entries(expectedCategories)) {
      const actualIds = BUILTIN_TEMPLATES
        .filter((template) => template.category === category)
        .map((template) => template.id);
      expect(actualIds.sort(), category).toEqual([...expectedIds].sort());
    }
  });

  it('keeps framing metadata aligned with the selected category', () => {
    for (const template of BUILTIN_TEMPLATES) {
      if (template.category === 'half') expect(template.shotType, template.id).toBe('half-body');
      if (template.category === 'seated') expect(template.shotType, template.id).toBe('seated');
      if (template.category === 'standing' || template.category === 'crouching') {
        expect(template.shotType, template.id).toBe('full-body');
      }
    }
  });

  it('offers every reviewed category for both genders', () => {
    for (const category of Object.keys(expectedCategories) as PoseCategory[]) {
      expect(new Set(BUILTIN_TEMPLATES.filter((template) => template.category === category).map((template) => template.gender)), category)
        .toEqual(new Set(['female', 'male']));
    }
  });
});
