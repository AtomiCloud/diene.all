import { createModuleRegistry, defineModule } from '@atomicloud/diene.frontend-utils/module';
import { landscape } from '@atomicloud/diene.frontend-utils/landscape';

declare const runtimeBinding: { readonly LANDSCAPE: string };

const activeLandscape = landscape({ source: 'binding', value: runtimeBinding.LANDSCAPE });
const profile = defineModule({
  id: 'profile',
  create: (config: { landscape: string }) => ({ landscape: config.landscape }),
});

const modules = createModuleRegistry();
await modules.register(profile, { landscape: activeLandscape }).unwrap();
