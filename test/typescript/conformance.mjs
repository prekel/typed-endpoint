import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';
import Ajv2020 from 'ajv/dist/2020.js';
import { compile } from 'json-schema-to-typescript';
import ts from 'typescript';

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(directory, '../..');
const generated = path.join(directory, '.generated');
mkdirSync(generated, { recursive: true });
const fixtures = JSON.parse(execFileSync('opam', [
  'exec', '--', 'dune', 'exec', '--root', '.',
  'test/conformance/typescript_fixture.exe',
], { cwd: root, encoding: 'utf8' }));
const unavoidableUnknown = new Set(['Any', 'Generic', 'OpenRecord', 'BooleanRefs']);
const files = [];
const assignments = [];
const commonValues = [null, true, false, 0, '', [], {}, ['A'], { value: 1 }];

// Ajv 8.17 recurses while compiling a fragment-only recursive reference in an
// embedded $id resource. Register each resource as a separate schema root, so
// its unchanged references are resolved in that resource's original scope.
function originalValidatorFor(schema, options) {
  const ajv = new Ajv2020(options);
  const resources = new Map();
  const maps = new Set(['properties', 'patternProperties', '$defs', 'definitions', 'dependentSchemas']);
  const lists = new Set(['allOf', 'anyOf', 'oneOf', 'prefixItems']);
  const values = new Set(['items', 'additionalProperties', 'unevaluatedProperties', 'unevaluatedItems', 'contains', 'propertyNames', 'not', 'if', 'then', 'else', 'contentSchema']);
  const visit = (value, root = false) => {
    if (typeof value === 'boolean') return value;
    const output = Object.fromEntries(Object.entries(value).map(([key, child]) => {
      if (maps.has(key)) return [key, Object.fromEntries(Object.entries(child).map(([name, schema]) => [name, visit(schema)]))];
      if (lists.has(key)) return [key, child.map(schema => visit(schema))];
      if (values.has(key)) return [key, visit(child)];
      return [key, child];
    }));
    if (!root && value.$id) {
      resources.set(value.$id, output);
      return { $ref: value.$id };
    }
    return output;
  };
  const root = visit(schema, true);
  for (const resource of resources.values()) ajv.addSchema(resource);
  return ajv.compile(root);
}

for (const fixture of fixtures) {
  const { name, original, exported, accept, reject } = fixture;
  const options = { strict: false, validateFormats: false, allErrors: true };
  const originalValidator = originalValidatorFor(original, options);
  const exportedValidator = new Ajv(options).compile(exported);
  for (const value of accept) {
    assert.equal(originalValidator(value), true, `${name}: original rejects ${JSON.stringify(value)}: ${JSON.stringify(originalValidator.errors)}`);
    assert.equal(exportedValidator(value), true, `${name}: export rejects ${JSON.stringify(value)}: ${JSON.stringify(exportedValidator.errors)}`);
    assignments.push(`const ${name}_${assignments.length}: import('./${name}.js').${name} = ${JSON.stringify(value)};`);
  }
  for (const value of reject) {
    assert.equal(originalValidator(value), false, `${name}: original accepts invalid ${JSON.stringify(value)}`);
    assert.equal(exportedValidator(value), false, `${name}: export accepts invalid ${JSON.stringify(value)}`);
  }
  for (const value of [...commonValues, ...accept, ...reject]) {
    assert.equal(exportedValidator(value), originalValidator(value), `${name}: export changes validation of ${JSON.stringify(value)}`);
  }
  const output = await compile(exported, name, { bannerComment: '' });
  const source = ts.createSourceFile(`${name}.d.ts`, output, ts.ScriptTarget.Latest, true);
  const visit = node => {
    assert.notEqual(node.kind, ts.SyntaxKind.AnyKeyword, `${name}: generated any`);
    if (!unavoidableUnknown.has(name)) {
      assert.notEqual(node.kind, ts.SyntaxKind.UnknownKeyword, `${name}: avoidable unknown`);
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  const filename = path.join(generated, `${name}.d.ts`);
  writeFileSync(filename, output);
  files.push(filename);
}

const wireFile = path.join(generated, 'wire.ts');
writeFileSync(wireFile, `${assignments.join('\n')}\n`);
files.push(wireFile, path.join(directory, 'assertions.ts'));
const program = ts.createProgram(files, {
  strict: true,
  noEmit: true,
  exactOptionalPropertyTypes: true,
  skipLibCheck: false,
  types: [],
  target: ts.ScriptTarget.ES2022,
  module: ts.ModuleKind.NodeNext,
  moduleResolution: ts.ModuleResolutionKind.NodeNext,
});
const diagnostics = ts.getPreEmitDiagnostics(program);
assert.equal(diagnostics.length, 0, ts.formatDiagnosticsWithColorAndContext(diagnostics, {
  getCanonicalFileName: filename => filename,
  getCurrentDirectory: () => root,
  getNewLine: () => '\n',
}));
const packageVersion = name => JSON.parse(readFileSync(path.join(directory, 'node_modules', name, 'package.json'), 'utf8')).version;
console.log(`${fixtures.length} schemas: validation, generated types, wire assignments and negative type checks passed (json-schema-to-typescript ${packageVersion('json-schema-to-typescript')}, TypeScript ${ts.version}).`);
