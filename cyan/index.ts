import { GlobType, StartTemplateWithLambda } from '@atomicloud/cyan-sdk';

const platformPattern = /^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?$/;

StartTemplateWithLambda(async i => {
  const platform = (
    await i.text('Platform name', 'carbon/platform', 'Lowercase DNS label used for <platform>.carbon')
  ).toLowerCase();

  if (!platformPattern.test(platform) || platform.length > 63) {
    throw new Error('Platform name must be a DNS-1123 label of at most 63 characters');
  }

  return {
    processors: [
      {
        name: 'cyan/default',
        files: [
          {
            root: 'templates/base',
            glob: '**/*',
            type: GlobType.Template,
            exclude: [],
          },
        ],
        config: {
          vars: { platform },
          parser: {
            varSyntax: [
              ['let__', '__'],
              ['# let__', '__'],
            ],
          },
        },
      },
    ],
    plugins: [],
  };
});
