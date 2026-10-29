// Extract only the pure schedule functions; never execute the website bootstrap.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { parse } from 'acorn';
import { analyze } from 'eslint-scope';

const input = process.argv[2];
if (!input) throw new Error('Pass the downloaded Spelunkr JavaScript bundle path.');
const source = await readFile(input, 'utf8');
const ast = parse(source, { ecmaVersion: 'latest', sourceType: 'module', ranges: true });
const scope = analyze(ast, { ecmaVersion: 2024, sourceType: 'module', optimistic: true });
const moduleScope = scope.scopes.find(s => s.type === 'module');
const declarations = new Map();
for (const node of ast.body) {
  if (node.type === 'FunctionDeclaration' || node.type === 'ClassDeclaration') {
    declarations.set(node.id.name, { node, code: source.slice(node.start, node.end), deps: new Set() });
  } else if (node.type === 'VariableDeclaration') {
    for (const decl of node.declarations) {
      if (decl.id.type !== 'Identifier') continue;
      declarations.set(decl.id.name, { node: decl, code: `${node.kind} ${source.slice(decl.start, decl.end)};`, deps: new Set() });
    }
  }
}
const owners = [...declarations.values()].sort((a, b) => a.node.start - b.node.start);
for (const variable of moduleScope.variables) {
  if (!declarations.has(variable.name)) continue;
  for (const ref of variable.references) {
    if (!ref.isRead()) continue;
    const owner = owners.find(d => ref.identifier.start >= d.node.start && ref.identifier.end <= d.node.end);
    owner?.deps.add(variable.name);
  }
}
const roots = { buildPlaylist: 'qg', hydrateVersion: 'I0', resolveAt: 'en' };
const selected = new Set();
function visit(name) {
  if (selected.has(name)) return;
  const decl = declarations.get(name);
  if (!decl) throw new Error(`Missing schedule dependency ${name}; upstream bundle changed.`);
  selected.add(name);
  for (const dependency of decl.deps) visit(dependency);
}
Object.values(roots).forEach(visit);
const sha256 = createHash('sha256').update(source).digest('hex');
const code = [...declarations.entries()].filter(([name]) => selected.has(name)).map(([, decl]) => decl.code).join('\n');
if (/\b(document|window|fetch|localStorage)\b/.test(code)) throw new Error('Schedule extraction unexpectedly includes browser or network code.');
await mkdir('web/vendor', { recursive: true });
await writeFile('web/vendor/schedule-engine.js', `// Spelunkr pure broadcast scheduler, extracted from the public production bundle.\n// Source: https://spelunkr.tv/assets/index-HVqlsCpR.js\n// SHA-256: ${sha256}\n// See PROVENANCE.md. Website UI/bootstrap is excluded.\n${code}\nexport { ${Object.entries(roots).map(([alias, name]) => `${name} as ${alias}`).join(', ')} };\n`);
await writeFile('server/vendor/provenance.json', JSON.stringify({ source: 'https://spelunkr.tv/assets/index-HVqlsCpR.js', sha256, engine: 5, extractedAt: new Date().toISOString(), declarations: selected.size }, null, 2) + '\n');
console.log(`Extracted ${selected.size} pure declarations (${code.length} characters), SHA-256 ${sha256}.`);
