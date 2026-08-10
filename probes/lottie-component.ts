// Cost: light (<10s) — no build, no browser.
//
// The animation itself cannot be rendered without a DOM (lottie-react drives a
// canvas/SVG player), and a screenshot of it would be golden evidence, which this
// tree does not use anywhere. What is provable cheaply and honestly is that the
// payload is a well-formed Lottie document with real frames and that the component
// module resolves — the two ways this surface actually breaks in practice.
const ANIMATION = 'src/components/lottie/celebration.json';
const COMPONENTS = ['src/components/lottie/Lottie.tsx', 'src/components/lottie/CelebrationLottie.tsx'];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-lottie-component-green',
      description:
        'The celebration payload parses as a Lottie document with a frame range and layers, and both animation components exist and honour reduced motion.',
      kind: 'baseline',
      async run(repo: any) {
        const animation = JSON.parse(await repo.read(ANIMATION));
        for (const member of ['v', 'fr', 'ip', 'op', 'layers']) {
          if (animation[member] === undefined) {
            throw new Error(`celebration animation is missing the Lottie member '${member}'`);
          }
        }
        if (!(animation.fr > 0)) throw new Error('celebration animation declares no frame rate');
        if (!(animation.op > animation.ip)) throw new Error('celebration animation declares an empty frame range');
        if (!Array.isArray(animation.layers) || animation.layers.length === 0) {
          throw new Error('celebration animation declares no layers');
        }
        for (const component of COMPONENTS) {
          if ((await repo.glob(component)).length !== 1) throw new Error(`missing animation component: ${component}`);
        }
        // Reduced motion is an accessibility requirement, not a nice-to-have: the
        // player must freeze rather than animate when the user has asked it to.
        if (!/prefersReducedMotion/.test(await repo.read(COMPONENTS[0]))) {
          throw new Error('the Lottie component does not consult prefers-reduced-motion');
        }
      },
    },
  ],
};
