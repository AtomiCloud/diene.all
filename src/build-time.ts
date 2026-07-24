// The `/build-time` entry point: the inlineable (client/build-time) value map
// for DefinePlugin-style static injection into a bundle. nextjs owns the
// DefinePlugin wiring; this lib owns the value map. Runtime env still wins over
// these frozen values where present.
export * from './lib/build-time.js';
