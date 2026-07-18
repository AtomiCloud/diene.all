const flavors = ['lapras', 'pichu', 'pikachu', 'raichu'] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-per-flavor-icons',
      description: 'Every landscape has source, Android density, and iOS catalog icons.',
      kind: 'baseline',
      async run(repo: any) {
        for (const flavor of flavors) {
          if ((await repo.glob(`assets/brand/icon-${flavor}.png`)).length !== 1) {
            throw new Error(`missing raster icon source for ${flavor}`);
          }
          if ((await repo.glob(`android/app/src/${flavor}/res/mipmap-*/ic_launcher.png`)).length < 5) {
            throw new Error(`incomplete Android icon set for ${flavor}`);
          }
          if ((await repo.glob(`ios/Runner/Assets.xcassets/AppIcon-${flavor}.appiconset/Contents.json`)).length !== 1) {
            throw new Error(`missing iOS AppIcon catalog for ${flavor}`);
          }
        }
      },
    },
  ],
};
