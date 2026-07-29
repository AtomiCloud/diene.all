# Withheld SIT journeys

Journeys in this folder are **authored but deliberately not run**. They are here so
the gap is named rather than silently absent — a reader of the collection can see
exactly which feature has no SIT proof and why.

`bruno.json` lists `withheld` in its `ignore` array, and nothing here carries a
`.bru` extension, so no runner can pick these up and no run can report them as
passing. They are also invisible to `scripts/ci/sit.sh`, which counts `*.bru`
files.

| Journey                                                     | Withheld because                                               |
| ----------------------------------------------------------- | -------------------------------------------------------------- |
| [castform Mercury delivery](./castform-mercury-delivery.md) | The D11 callback-contract re-ruling is still open.             |
| [app-handoff mint/redeem](./app-handoff-mint-redeem.md)     | The endpoints are absent from the consumed AuthEngine package. |

## The rule these follow

A withheld journey must not pretend. It is not written as a passing request against
a stub, it is not written as a skipped test that reports green, and it is not
quietly deleted. It stays visible, with the reason and the condition that would
un-withhold it.

Un-withholding one means moving the request into a numbered folder as a real `.bru`
file, removing its row above, and — for the mint/redeem pair — first confirming the
endpoints exist in the pinned `AtomiCloud.Diene.AuthEngine` version.
