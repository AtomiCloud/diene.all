'use client';

import LottiePlayer from 'lottie-react';
import { prefersReducedMotion } from '@atomicloud/diene.frontend-utils/a11y';

/**
 * Lottie component (ported from argon): renders an animation payload and
 * honors prefers-reduced-motion by freezing on the first frame.
 */
export function Lottie({
  animationData,
  loop = true,
  className,
}: {
  readonly animationData: object;
  readonly loop?: boolean;
  readonly className?: string;
}) {
  const reduced = prefersReducedMotion({
    matches: () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches,
    subscribe: () => () => undefined,
  });
  return (
    <LottiePlayer animationData={animationData} loop={loop && !reduced} autoplay={!reduced} className={className} />
  );
}
