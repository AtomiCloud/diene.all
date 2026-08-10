// dts-bundle-generator config: emit flat, self-contained declarations for all
// three published entry points from a SINGLE TypeScript program. Sharing the
// program pays zod's heavy type-loading cost once instead of per entry.
module.exports = {
  compilationOptions: {
    preferredConfigPath: './tsconfig.json',
  },
  entries: [
    { filePath: './src/index.ts', outFile: './dist/index.d.ts', noCheck: true },
    { filePath: './src/build-time.ts', outFile: './dist/build-time.d.ts', noCheck: true },
    { filePath: './src/test-helper/index.ts', outFile: './dist/test-helper.d.ts', noCheck: true },
  ],
};
