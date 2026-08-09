import { staticGate } from './lib/cli-contract.ts';

export default staticGate('cli-distroless-base', 'distroless', {
  path: 'infra/Dockerfile',
  find: 'FROM gcr.io/distroless/cc-debian12:nonroot AS runtime',
  replace: 'FROM debian:12-slim AS runtime',
});
