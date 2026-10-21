import type { Nullary } from './.generated/Nullary.js';
import type { Payload } from './.generated/Payload.js';
import type { Poly } from './.generated/Poly.js';
import type { Tuple } from './.generated/Tuple.js';
import type { Result } from './.generated/Result.js';
import type { Fields } from './.generated/Fields.js';
import type { Primitives } from './.generated/Primitives.js';
import type { Union } from './.generated/Union.js';
import type { Intersection } from './.generated/Intersection.js';
import type { RootRecursive } from './.generated/RootRecursive.js';
import type { Recursive } from './.generated/Recursive.js';
import type { Nested } from './.generated/Nested.js';
import type { Mutual } from './.generated/Mutual.js';
import type { Generic } from './.generated/Generic.js';
import type { OpenRecord } from './.generated/OpenRecord.js';
import type { Dictionary } from './.generated/Dictionary.js';
import type { Collection } from './.generated/Collection.js';
import type { StringEnum } from './.generated/StringEnum.js';
import type { Literal } from './.generated/Literal.js';
import type { CompositeEnum } from './.generated/CompositeEnum.js';
import type { TypedTail } from './.generated/TypedTail.js';
import type { Any } from './.generated/Any.js';
import type { Never } from './.generated/Never.js';
import type { BooleanRefs } from './.generated/BooleanRefs.js';

type Equal<A, B> = (<T>() => T extends A ? 1 : 2) extends (<T>() => T extends B ? 1 : 2) ? true : false;
type Expect<T extends true> = T;

type Checks = [
  Expect<Equal<Nullary, ['A'] | ['B']>>,
  Expect<Equal<Payload, ['empty'] | ['Value', number] | ['Pair', string, boolean] | ['Row', { name: string; count: number }]>>,
  Expect<Equal<Poly, ['A'] | ['Value', number] | ['Pair', string, boolean]>>,
  Expect<Equal<Tuple, [number, string]>>,
  Expect<Equal<Result, ['Ok', number] | ['Error', string]>>,
  Expect<Equal<Fields, { count: number; nullable: string | null; optional?: string | null; wire: string; wide: string; values: boolean[] }>>,
  Expect<Equal<Primitives, { small: number; wide: number; number: number; letter: string; data: string; empty: null }>>,
  Expect<Equal<Union, number | string>>,
  Expect<Equal<Intersection, string>>,
  Expect<Equal<RootRecursive['next'], RootRecursive | null>>,
  Expect<Equal<Recursive['value'], number>>,
  Expect<Equal<Recursive['next'], Recursive | null>>,
  Expect<Equal<Nested['left']['value'], number>>,
  Expect<Equal<Nested['right']['value'], string>>,
  Expect<Equal<NonNullable<Nested['right']['next']>['value'], string>>,
  Expect<Equal<NonNullable<NonNullable<Mutual['next']>['previous']>['next'], Mutual['next']>>,
  Expect<Equal<Generic['value'], unknown>>,
  Expect<Equal<OpenRecord['value'], number>>,
  Expect<Equal<OpenRecord[string], unknown>>,
  Expect<Equal<Dictionary[string], number>>,
  Expect<Equal<Collection, string[]>>,
  Expect<Equal<StringEnum, 'red' | 'blue'>>,
  Expect<Equal<Literal, { kind: 'fixed'; count: 2 }>>,
  Expect<Equal<CompositeEnum, ['a'] | ['b']>>,
  Expect<Equal<TypedTail, [number, ...string[]]>>,
  Expect<Equal<Any, unknown>>,
  Expect<Equal<Never, never>>,
  Expect<Equal<BooleanRefs['anything'], unknown>>,
  Expect<Equal<BooleanRefs['nothing'], undefined>>,
];

// @ts-expect-error Unknown constructor tags must be rejected.
const badTag: Nullary = ['C'];
// @ts-expect-error Constructor payloads retain their types.
const badPayload: Payload = ['Value', 'wrong'];
// @ts-expect-error Nullary constructors cannot acquire a payload.
const extraPayload: Payload = ['empty', 1];
// @ts-expect-error Tuples retain positional types.
const wrongTuple: Tuple = ['wrong', 1];
// @ts-expect-error Tuples are closed.
const longTuple: Tuple = [1, 'x', true];
// @ts-expect-error Result success values are integers.
const wrongResult: Result = ['Ok', 'wrong'];
// @ts-expect-error Recursion must not become unknown.
const wrongRecursive: Recursive = { value: 1, next: { value: 'wrong', next: null } };
// @ts-expect-error Resource scopes with identical definition names stay distinct.
const wrongNested: Nested['right'] = { value: 1, next: null };
// @ts-expect-error Optional does not mean untyped.
const wrongOptional: Fields['optional'] = 42;
// @ts-expect-error Arbitrary dictionary keys retain the value type.
const wrongDictionary: Dictionary = { a: 'wrong' };
// @ts-expect-error Typed tuple tails must be strings.
const wrongTail: TypedTail = [1, 2];
// @ts-expect-error An empty schema accepts no values.
const impossible: Never = null;
// @ts-expect-error Unrestricted JSON remains unknown, not any.
const unknownAsNumber: number = null as unknown as Any;

export type { Checks };
