import { describe, it } from 'bun:test';
import should from 'should';

// The DI wiring: modules are declared once, registered under UNIQUE ids, and
// resolved through the registry — never constructed ad hoc by consumers. The
// registration surface is asserted over the wiring source because buildModules
// pulls in React component modules (the Problem view) that need no DOM to
// import but do drag the client graph into a unit-tier process; the resolution
// path itself is proven at the int tier
// (tests/integration/module-failures.test.ts).

const WIRING = 'src/adapters/atomi/modules.ts';

const idsIn = (source: string): string[] =>
  [...source.matchAll(/^\s{2}([A-Za-z]+): '([a-z-]+)',$/gm)].map(match => match[2] ?? '');

describe('module wiring', () => {
  it('should declare every module id exactly once', async () => {
    // Arrange
    const ids = idsIn(await Bun.file(WIRING).text());

    // Assert — a duplicate id makes registration fail at boot; uniqueness is the
    // invariant that keeps that failure branch unreachable in production.
    should(ids.length).be.above(1);
    should(new Set(ids).size).equal(ids.length);
  });

  it('should register exactly the modules it resolves', async () => {
    // Arrange
    const source = await Bun.file(WIRING).text();
    const registered = [...source.matchAll(/registry\.register\((\w+)Module, config\)/g)].map(match => match[1]);
    const resolved = [...source.matchAll(/required<.*?>\(registry, MODULE_IDS\.(\w+)\)/g)].map(match => match[1]);

    // Assert — every registered module is resolved and every resolved module was
    // registered, so `buildModules` never hands back a half-built surface.
    should(registered.length).be.above(1);
    should([...registered].sort()).deepEqual([...resolved].sort());
  });

  it('should surface a registration or resolution failure loudly', async () => {
    // Arrange — ids are unique by construction, so both failure branches are
    // unreachable through the real registry. They must still throw naming the
    // offending id rather than degrade to a partial module surface.
    const source = await Bun.file(WIRING).text();

    // Assert
    should(source).match(/throw new Error\(`module registration failed: \$\{error\.kind\} \(\$\{error\.id\}\)`\)/);
    should(source).match(/throw new Error\(`module resolution failed: \$\{error\.kind\} \(\$\{error\.id\}\)`\)/);
  });

  it('should resolve modules through the registry rather than constructing them', async () => {
    // Arrange — a consumer that called createProblemViewRegistry itself would get
    // a SECOND registry, and registered views would silently not apply.
    const source = await Bun.file(WIRING).text();
    const consumers = ['src/adapters/atomi/Providers.tsx', 'src/components/home/SystemPanel.tsx'];

    // Assert — the factories appear only in the wiring file.
    should(source).match(/createProblemViewRegistry<ReactNode>\(defaultProblemView\)/);
    for (const consumer of consumers) {
      should(await Bun.file(consumer).text()).not.match(/createProblemViewRegistry\(/);
    }
  });
});
