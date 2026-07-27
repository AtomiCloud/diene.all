import { createInMemoryPersistence, landscapeFixtures } from '@atomicloud/diene.frontend-utils/test-helper';

const persistence = createInMemoryPersistence();
const source = landscapeFixtures.binding('lapras');

// Pass `source` and `persistence` through the consumer's own wiring layer.
