# class-validator → zod migration audit (C0 note)

The helium seed (`nitroso/helium src/system/loader.ts`) validated its root config
with **class-validator** + **class-transformer**. This lib migrates that contract
to **zod**. Audited for semantics zod cannot express 1:1.

## Finding: no expressiveness gap

Every class-validator behavior the seed relied on is expressible in zod, in most
cases more explicitly:

| helium (class-validator / class-transformer)                                                | zod equivalent                                                    | note                                                           |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------- |
| `@IsNumber()` / `@IsString()` / `@IsBoolean()`                                              | `z.number()` / `z.string()` / `z.boolean()`                       | direct                                                         |
| `enableImplicitConversion: true` (implicit string→number/boolean from the TS `design:type`) | `z.coerce.number()` / `z.coerce.boolean()` per field              | **migration mechanics**, not an expressiveness gap — see below |
| `skipMissingProperties: false` (all properties required)                                    | zod fields are required by default; opt out with `.optional()`    | direct, and more explicit                                      |
| nested `@ValidateNested()` + `@Type()`                                                      | nested `z.object({...})`                                          | direct                                                         |
| `@IsOptional()`                                                                             | `.optional()`                                                     | direct                                                         |
| aggregated error list (`errors.toString()`)                                                 | `ConfigValidationError` aggregates `error.issues` per dotted path | improved (readable per-path messages)                          |

## The one nuance to record

`class-transformer`'s `enableImplicitConversion` coerces a value implicitly from
the property's reflected TypeScript type, so a single flag covered every field.
zod has no reflection: coercion is **per-field and explicit** (`z.coerce.number()`).
This is a difference in migration MECHANICS, not in what can be expressed — the
resulting contract is strictly more explicit and matches M31 (coercion is zod's
job, never a hand-rolled `Number()`). Consumers must therefore declare
env-overridable numeric/boolean fields with `z.coerce.*`; this is documented in
[the config standard](../standards/config/index.md#env-override-contract).

## Verdict

No C0 contract change is required: zod expresses the full class-validator surface
the family used. The only actionable guidance — "declare env-overridable scalars
with `z.coerce.*`" — is captured in the config standard and the usage skill.
