import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

let sourceAvailable = false;
JSON.parse('1', (_key, value, context) => {
  sourceAvailable = context?.source === '1';
  return value;
});
if (!sourceAvailable || typeof JSON.rawJSON !== 'function') {
  throw new Error('Client conformance requires Node.js with JSON.parse reviver context.source and JSON.rawJSON');
}

const wire = readFileSync(0, 'utf8');
const ordinary = JSON.parse(wire);
const lossless = text => JSON.parse(text, (_key, value, context) =>
  typeof value === 'number' && Number.isInteger(value) ? BigInt(context.source) : value);
const precise = lossless(wire);
const encoded = JSON.stringify(precise, (_key, value) =>
  typeof value === 'bigint' ? JSON.rawJSON(value.toString()) : value);
assert.deepEqual(lossless(encoded), precise);
assert.equal(ordinary.numeric_schema.properties.value.type, 'integer');
assert.equal(ordinary.native_schema.properties.value.type, 'integer');
assert.equal(ordinary.textual_schema.properties.value.type, 'string');

ordinary.fixtures.forEach((fixture, index) => {
  const exact = BigInt(fixture.decimal);
  assert.equal(precise.fixtures[index].numeric.value, exact);
  assert.equal(fixture.textual.value, fixture.decimal);
  assert.equal(typeof fixture.numeric.value, 'number');
  assert.equal(typeof fixture.textual.value, 'string');
  assert.equal(Number.isSafeInteger(fixture.numeric.value), index === 0);
  // 2^53 is exact, although it is no longer a safe integer.
  assert.equal(BigInt(fixture.numeric.value) === exact, index < 2);
});
const native = BigInt(ordinary.native.decimal);
assert.equal(precise.native.numeric.value, native);
assert.equal(BigInt(ordinary.native.numeric.value) === native, native <= BigInt(Number.MAX_SAFE_INTEGER));
const ordinaryAgain = JSON.parse(JSON.stringify(ordinary));
assert.notEqual(BigInt(ordinaryAgain.fixtures[2].numeric.value), 9007199254740993n);
console.log('Client numbers: OCaml wire, integer/string schemas, unsafe Number and lossless numeric round-trip passed');
