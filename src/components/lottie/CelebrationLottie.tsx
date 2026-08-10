'use client';

import { Lottie } from './Lottie';
import celebration from './celebration.json';

/** The finish page's celebration animation (lottie smoke's render surface). */
export function CelebrationLottie() {
  return <Lottie animationData={celebration} loop={false} className="h-40 w-40" />;
}
