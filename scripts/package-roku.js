import { rm } from 'node:fs/promises';
import { ProgramBuilder } from 'brighterscript';

if (process.argv.length > 2) throw new Error('This standalone build connects directly to Spelunkr. No adapter URL is needed.');
const builder = new ProgramBuilder();
try {
  await builder.run({ project: 'bsconfig.json', createPackage: true, copyToStaging: true, sourceMap: false });
  const errors = builder.getDiagnostics().filter(d => d.severity === 1);
  if (errors.length) throw new Error(`Roku build failed with ${errors.length} errors.`);
  await rm('dist/adapter-config.json', { force: true });
  console.log('\nBuilt dist/spelunkr-roku.zip\nStandalone: schedules from Spelunkr, video from the Internet Archive.\nYour computer does not need to be running.');
} finally {
  builder.dispose();
}
