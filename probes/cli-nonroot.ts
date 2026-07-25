import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-nonroot', 'nonroot', {
  path: 'infra/Dockerfile',
  find: 'FROM gcr.io/distroless/cc-debian12:nonroot AS runtime',
  replace: 'FROM gcr.io/distroless/cc-debian12:debug AS runtime',
});
